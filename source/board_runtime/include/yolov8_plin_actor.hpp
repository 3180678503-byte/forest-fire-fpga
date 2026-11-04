#pragma once
#include "pipeline/actor/base_actors.hpp"
#include "compile_fpai_target.hpp"
#include "icraft_utils.hpp"
#include <chrono>
#include <exception>
#include <mutex>
#include <filesystem>
#include <fstream>
#include <icraft-xrt/core/session.h>

// Same interface used by the vendor camera actor. Its ImageMake output is
// written directly to the first HardOp input of the corresponding Session.
template<class Shape> bool shape_matches(const Shape& shape,std::initializer_list<int64_t> expected){
    return shape.size()==expected.size()&&std::equal(shape.begin(),shape.end(),expected.begin());
}
class Yolov8PLinActor : public fpai::BaseActor<InputMessageForIcore,IcoreMessageForPost> {
public:
    Yolov8PLinActor(fpai::FPAIDevice& device,BufferManager& buffers,
                   const std::string& json,const std::string& raw,const std::string& dump_directory="",
                   std::mutex *device_io_mutex=nullptr)
        : BaseActor(buffers),device_(device),network_(loadNetwork(json,raw)),dump_directory_(dump_directory),device_io_mutex_(device_io_mutex) {
        if(network_.inputs().size()!=1)throw std::runtime_error("Expected one physical ImageMake input");
        auto type=network_.inputs()[0].tensorType();
        if(!shape_matches(type->shape,{1,416,416,3})||!type->element_dtype.getStorageType().is<icraft::xir::IntegerType>())
            throw std::runtime_error("PLIN model must accept NHWC [1,416,416,3] SINT8 BGR");
        auto storage=type->element_dtype.getStorageType().cast<icraft::xir::IntegerType>();
        if(storage.bits()!=8||storage.isUInt8())throw std::runtime_error("Live ImageMake needs signed 8-bit BGR storage, pixel minus 128");
        // Remove only the generated Input op. Keep normalization/quantization
        // operations unless the compiler has folded them into the first layer.
        auto viewed=network_.viewExcept({0});
        for(size_t i=0;i<buffers.getChunkCount();++i){
            auto session=initSession("zg330",viewed,device_,-1,true,false,false);
            session.apply();
            auto forwards=session.getForwards();
            if(forwards.empty()||!std::get<0>(forwards.front()).is<icraft::xir::HardOp>()||
               !std::get<1>(forwards.front()).is<fpai::FPAIBackend>())
                throw std::runtime_error("PLIN first forward must be a ZG330 HardOp");
            auto op=std::get<0>(forwards.front());
            if(op->inputs.empty())throw std::runtime_error("PLIN first HardOp has no input");
            auto head_type=op->inputs[0].tensorType();
            if(!shape_matches(head_type->shape,{1,416,416,3})||
               head_type->element_dtype.getStorageType().bits()!=8)
                throw std::runtime_error("ImageMake destination must hold 416x416 RGB bytes");
            sessions_.push_back(session);
        }
    }
    ~Yolov8PLinActor(){this->stop();}
    std::vector<icraft::xrt::Session>& sessions(){return sessions_;}
    void verifySavedInputs(){
        size_t mismatches=0,bytes=0;
        for(auto& saved:validation_frames_){
            saved.input.write(0,saved.pixels.data(),saved.pixels.size());
            auto reference=sessions_[saved.buffer].forward({saved.input});
            if(reference.size()!=6)throw std::runtime_error("Reference head count mismatch");
            for(size_t j=0;j<6;++j){
                if(!reference[j].waitForReady(std::chrono::milliseconds(10000)))throw std::runtime_error("Reference sync timeout");
                auto host=reference[j].to(icraft::xrt::HostDevice::MemRegion());
                auto actual=host.data().cptr();
                for(size_t k=0;k<saved.heads[j].size();++k){++bytes;if(actual[k]!=saved.heads[j][k])++mismatches;}
            }
            device_.reset(1);
        }
        std::cout<<"SERIAL_REFERENCE samples="<<validation_frames_.size()<<" compared_bytes="<<bytes<<" mismatched_bytes="<<mismatches<<std::endl;
        if(mismatches)throw std::runtime_error("Overlap output differs from serial same-input reference");
    }
    bool failed()const {return failed_.load();}
    void rethrow_failure(){std::lock_guard<std::mutex> lock(failure_mutex_);if(failure_)std::rethrow_exception(failure_);}
protected:
    void loop()override {
        try{
            if(!this->input_queue_||!this->output_queue_)throw std::runtime_error("Unbound actor queues");
            while(!this->stop_flag_){
#ifdef FMQL_PROFILE
                auto queue_begin=fmql_profile::now_ns();
#endif
                InputMessageForIcore incoming;
                if(!this->input_queue_->wait_and_pop(incoming))break;
                IcoreMessageForPost outgoing{};outgoing.meta=incoming.meta;
#ifdef FMQL_PROFILE
                auto &p=outgoing.meta.profile;
                p.npu_dequeued_ns=fmql_profile::now_ns();
                p.npu_queue_wait_ms=fmql_profile::ms(p.npu_dequeued_ns,queue_begin);
#endif
                if(incoming.meta.error_input||incoming.meta.invalid_ps_frame){
                    outgoing.meta.error_input=true;this->output_queue_->push(std::move(outgoing));continue;
                }
                if(incoming.meta.source_id!=0||incoming.meta.buffer_index<0||
                   size_t(incoming.meta.buffer_index)>=sessions_.size()||incoming.image_tensors.size()!=1)
                    throw std::runtime_error("Invalid PLIN camera message");
                // incoming Tensor is already bound to the ImageMake PLDDR
                // destination by vendor SDICameraInputActor::setData.
#ifdef FMQL_PROFILE
                auto lock_begin=fmql_profile::now_ns();
#endif
                std::unique_lock<std::mutex> device_lock;
                if(device_io_mutex_)device_lock=std::unique_lock<std::mutex>(*device_io_mutex_);
#ifdef FMQL_PROFILE
                p.npu_lock_ns=fmql_profile::now_ns();
                p.npu_lock_wait_ms=fmql_profile::ms(p.npu_lock_ns,lock_begin);
#endif
                if(!dump_directory_.empty()&&processed_==0){
                    std::filesystem::create_directories(dump_directory_);
                    auto captured=incoming.image_tensors[0].to(icraft::xrt::HostDevice::MemRegion());
                    std::ofstream dump(dump_directory_+"/input_nhwc_sint8_bgr.bin",std::ios::binary);
                    dump.write(captured.data().cptr(),416*416*3);
                    if(!dump)throw std::runtime_error("Failed to dump live model input");
                }
                SavedFrame saved;
                const char* validate=std::getenv("FMQL_VALIDATE_COUNT");
                const char* stride_env=std::getenv("FMQL_VALIDATE_STRIDE");
                size_t stride=stride_env?size_t(std::max(1,std::atoi(stride_env))):1;
                bool save=validate&&processed_%stride==0&&validation_frames_.size()<size_t(std::max(0,std::atoi(validate)));
                if(save){
                    saved.input=incoming.image_tensors[0];saved.buffer=incoming.meta.buffer_index;
                    auto host=saved.input.to(icraft::xrt::HostDevice::MemRegion());
                    auto data=host.data().cptr();saved.pixels.assign(data,data+416*416*3);
                }
                auto begin=std::chrono::steady_clock::now();
                auto outputs=sessions_[incoming.meta.buffer_index].forward(incoming.image_tensors);
#ifdef FMQL_PROFILE
                auto forward_done=fmql_profile::now_ns();
                p.npu_forward_call_ms=std::chrono::duration<double,std::milli>(fmql_profile::Clock::now()-begin).count();
#endif
                if(outputs.size()!=6)throw std::runtime_error("Expected six YOLOv8 raw heads");
                for(int i=0;i<6;++i){
#ifdef FMQL_PROFILE
                    auto ready_start=fmql_profile::now_ns();
#endif
                    if(!outputs[i].waitForReady(std::chrono::milliseconds(10000)))
                        throw std::runtime_error("NPU output synchronization timeout");
#ifdef FMQL_PROFILE
                    p.npu_ready_ms+=fmql_profile::ms(fmql_profile::now_ns(),ready_start);
#endif
                    int side=52>>(i/2),channels=i%2?2:64;
                    auto dtype=outputs[i].dtype();
                    if(!shape_matches(dtype->shape,{1,side,side,channels})||
                       dtype->element_dtype.getStorageType().bits()!=32)
                        throw std::runtime_error("Expected ordered NHWC FP32 box/class heads");
                    // Output transfer only: no PS preprocessing or upload on
                    // the input path. Snapshot outputs before releasing NPU.
#ifdef FMQL_PROFILE
                    auto download_start=fmql_profile::now_ns();
#endif
                    outgoing.icore_tensors.push_back(outputs[i].to(icraft::xrt::HostDevice::MemRegion()));
#ifdef FMQL_PROFILE
                    p.npu_download_ms+=fmql_profile::ms(fmql_profile::now_ns(),download_start);
#endif
                }
#ifdef FMQL_PROFILE
                auto reset_start=fmql_profile::now_ns();
#endif
                if(save){
                    for(int j=0;j<6;++j){
                        size_t side=52>>(j/2),channels=j%2?2:64;
                        auto data=outgoing.icore_tensors[j].data().cptr();
                        saved.heads[j].assign(data,data+side*side*channels*sizeof(float));
                    }
                    validation_frames_.push_back(std::move(saved));
                }
                device_.reset(1);
#ifdef FMQL_PROFILE
                p.npu_done_ns=fmql_profile::now_ns();
                p.npu_reset_ms=fmql_profile::ms(p.npu_done_ns,reset_start);
                p.npu_lock_ms=fmql_profile::ms(p.npu_done_ns,p.npu_lock_ns);
#endif
                if(device_lock.owns_lock())device_lock.unlock();
                double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
                spdlog::info("[NPU][buffer={}] forward_sync_download_ms={:.3f}",incoming.meta.buffer_index,ms);
#ifdef FMQL_PROFILE
                auto hash_start=fmql_profile::now_ns();
#endif
                uint64_t hash=1469598103934665603ULL;
                for(int i=0;i<6;++i){
                    int side=52>>(i/2),channels=i%2?2:64;
                    auto data=reinterpret_cast<const unsigned char*>(outgoing.icore_tensors[i].data().cptr());
                    // Hash all four bytes of each sampled FP32 value. The low
                    // byte alone is often always zero after BF16 expansion.
                    for(size_t offset=0;offset<side*side*channels*sizeof(float);offset+=128){
                        for(size_t b=0;b<sizeof(float);++b){hash^=data[offset+b];hash*=1099511628211ULL;}
                    }
                }
#ifdef FMQL_PROFILE
                p.npu_hash_ms=fmql_profile::ms(fmql_profile::now_ns(),hash_start);
#endif
                spdlog::info("[NPU][sequence={}] sampled_output_hash={:#x}",processed_+1,hash);
                if(!dump_directory_.empty()&&processed_==0){
                    for(int i=0;i<6;++i){
                        int side=52>>(i/2),channels=i%2?2:64;
                        std::ofstream dump(dump_directory_+"/head_"+std::to_string(i)+".bin",std::ios::binary);
                        dump.write(outgoing.icore_tensors[i].data().cptr(),side*side*channels*sizeof(float));
                        if(!dump)throw std::runtime_error("Failed to dump live NPU head");
                    }
                }
#ifdef FMQL_PROFILE
                p.npu_enqueued_ns=fmql_profile::now_ns();
#endif
                ++processed_;
                this->output_queue_->push(std::move(outgoing));
            }
        }catch(...){
            {std::lock_guard<std::mutex> lock(failure_mutex_);failure_=std::current_exception();}
            failed_.store(true);this->stop_flag_.store(true);
            // Keep the downstream queue alive until main coordinates shutdown.
            spdlog::error("YOLOv8 NPU actor failed; stopping the application");
        }
    }
private:
    struct SavedFrame {int buffer=0;icraft::xrt::Tensor input;std::vector<char> pixels;std::array<std::vector<char>,6> heads;};
    std::vector<SavedFrame> validation_frames_;
    fpai::FPAIDevice& device_;
    icraft::xir::Network network_;
    std::vector<icraft::xrt::Session> sessions_;
    std::atomic<bool> failed_{false};
    std::mutex failure_mutex_;
    std::exception_ptr failure_;
    std::string dump_directory_;
    uint64_t processed_=0;
    std::mutex *device_io_mutex_;
};
