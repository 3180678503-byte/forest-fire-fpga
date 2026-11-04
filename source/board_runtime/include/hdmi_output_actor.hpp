#pragma once
#include "pipeline/actor/base_actors.hpp"
#include "et_device.hpp"
#include <opencv2/opencv.hpp>
#include <functional>
#include <mutex>
#include <exception>
#include <atomic>
#include <cstdlib>
#include <cstring>

namespace fmql_video {
// Own host pixels and the scanout source until all actors are stopped.
// Software submission/readback is distinct from physical HDMI scan completion.
template<class Message>
class HDMIOutputActor:public fpai::BaseActor<Message,void> {
public:
    using Post=std::function<void(const Message&,cv::Mat&)>;
    HDMIOutputActor(BufferManager& manager,std::string group,fpai::FPAIDevice device,
                    int w,int h,Post post,std::mutex* device_lock)
        :fpai::BaseActor<Message,void>(manager),group_(std::move(group)),device_(device),
         w_(w),h_(h),post_(std::move(post)),device_lock_(device_lock),pixels_(size_t(w)*h*2) {
        if(w!=1920||h!=1080)throw std::runtime_error("HDMI sink requires verified 1920x1080 pixels");
        display_=device_.getMemRegion("udma").malloc(pixels_.size(),false);
        const char* check=std::getenv("FMQL_HDMI_VERIFY_COUNT");
        verify_limit_=check?std::max(0,std::atoi(check)):0;
        if(verify_limit_)readback_.resize(pixels_.size());
        spdlog::info("[HDMI_BUFFER] address={} bytes={} verify_limit={}",display_->begin.addr(),pixels_.size(),verify_limit_);
    }
    ~HDMIOutputActor(){this->stop();}
    bool failed()const{return failed_.load();}
    uint64_t submittedCount()const{return submitted_.load();}
    void rethrow_failure(){if(error_)std::rethrow_exception(error_);}
    void finish(){
        spdlog::info("[HDMI_STATS] submitted={} skipped_invalid={} readback_checked={} readback_mismatch_bytes={}",
                     submitted_.load(),invalid_.load(),checked_,mismatches_);
        rethrow_failure();
    }
protected:
    void loop()override {
        try {
            while(!this->stop_flag_) {
#ifdef FMQL_PROFILE
                auto pop_begin=fmql_profile::now_ns();
#endif
                Message msg{};if(!this->input_queue_->wait_and_pop(msg))break;
                int index=msg.meta.buffer_index;if(index<0)continue;
#ifdef FMQL_PROFILE
                auto &p=msg.meta.profile;p.display_dequeued_ns=fmql_profile::now_ns();
                p.display_queue_wait_ms=fmql_profile::ms(p.display_dequeued_ns,pop_begin);
#endif
                bool owned=true;
                auto release=[&]{if(owned){owned=false;this->buffer_manager_.returnIndex(group_,index);}};
                try {
                    if(msg.meta.error_input||msg.meta.invalid_ps_frame){
                        ++invalid_;spdlog::warn("[HDMI_SKIP] buffer={} invalid_ps={} error_input={}",index,msg.meta.invalid_ps_frame,msg.meta.error_input);
                    }else {
                        auto& chunk=this->buffer_manager_.getChunk(group_,index);
                        {
                            auto lock=acquire();
#ifdef FMQL_PROFILE
                            auto begin=fmql_profile::now_ns();
#endif
                            chunk.read(reinterpret_cast<char*>(pixels_.data()),0,pixels_.size());
#ifdef FMQL_PROFILE
                            p.ps_read_ms=fmql_profile::ms(fmql_profile::now_ns(),begin);
#endif
                        }
                        cv::Mat image(h_,w_,CV_8UC2,pixels_.data());
                        if(post_)post_(msg,image);
#ifdef FMQL_PROFILE
                        auto submit_begin=fmql_profile::now_ns();
#endif
                        {
                            auto lock=acquire();
                            display_.write(0,reinterpret_cast<char*>(pixels_.data()),pixels_.size());
                            device_.defaultRegRegion().write(0x40080054,display_->begin.addr()>>3);
                            if(checked_<verify_limit_){
                                display_.read(reinterpret_cast<char*>(readback_.data()),0,readback_.size());
                                size_t wrong=0;for(size_t i=0;i<pixels_.size();++i)wrong+=pixels_[i]!=readback_[i];
                                mismatches_+=wrong;++checked_;
                                if(wrong)throw std::runtime_error("HDMI scanout source memory readback mismatch");
                            }
                        }
                        ++submitted_;
#ifdef FMQL_PROFILE
                        p.hdmi_submit_ms=fmql_profile::ms(fmql_profile::now_ns(),submit_begin);
#endif
                    }
                    release();
#ifdef FMQL_PROFILE
                    p.display_done_ns=fmql_profile::now_ns();
                    p.display_work_ms=fmql_profile::ms(p.display_done_ns,p.display_dequeued_ns);
                    p.e2e_ms=fmql_profile::ms(p.display_done_ns,p.capture_start_ns);
                    fmql_profile::emit(p);
#endif
                }catch(...){release();throw;}
            }
        }catch(...){error_=std::current_exception();failed_=true;}
    }
private:
    std::unique_lock<std::mutex> acquire(){
        return device_lock_?std::unique_lock<std::mutex>(*device_lock_):std::unique_lock<std::mutex>();
    }
    std::string group_;fpai::FPAIDevice device_;int w_,h_;Post post_;std::mutex* device_lock_;
    icraft::xrt::MemChunk display_;std::vector<uint8_t> pixels_,readback_;
    int verify_limit_=0,checked_=0;size_t mismatches_=0;
    std::atomic<uint64_t> submitted_{0},invalid_{0};std::atomic<bool> failed_{false};std::exception_ptr error_;
};
}
