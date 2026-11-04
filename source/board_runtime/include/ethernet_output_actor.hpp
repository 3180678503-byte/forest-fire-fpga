#pragma once
#include "ethernet_video_sink.hpp"
#include "pipeline/actor/base_actors.hpp"
#include <opencv2/opencv.hpp>
#include <functional>

namespace fmql_video {
template<class Message>
class EthernetOutputActor:public fpai::BaseActor<Message,void> {
public:
    using Post=std::function<void(const Message&,cv::Mat&)>;
    EthernetOutputActor(BufferManager& manager,std::string group,int w,int h,Post post,
                        std::mutex* device_lock,VideoOptions options)
        :fpai::BaseActor<Message,void>(manager),group_(std::move(group)),w_(w),h_(h),
         post_(std::move(post)),device_lock_(device_lock),data_(size_t(w)*h*2),sink_(std::move(options)) {}
    ~EthernetOutputActor(){this->stop();}
    bool failed()const{return failed_.load()||sink_.failed();}
    void rethrow_failure(){if(error_)std::rethrow_exception(error_);sink_.rethrow_failure();}
    void finish(){sink_.finish();rethrow_failure();}
protected:
    void loop()override {
        try {
            while(!this->stop_flag_) {
#ifdef FMQL_PROFILE
                auto pop_begin=fmql_profile::now_ns();
#endif
                Message msg;if(!this->input_queue_->wait_and_pop(msg))break;
#ifdef FMQL_PROFILE
                auto &p=msg.meta.profile;p.display_dequeued_ns=fmql_profile::now_ns();
                p.display_queue_wait_ms=fmql_profile::ms(p.display_dequeued_ns,pop_begin);
#endif
                int index=msg.meta.buffer_index;if(index<0)continue;
                try {
                    if(msg.meta.invalid_ps_frame){
                        spdlog::warn("[ETH_DISPLAY] skipped_invalid_ps_frame buffer={}",index);
                    }
                    if(!msg.meta.error_input&&!msg.meta.invalid_ps_frame) {
                        auto& chunk=this->buffer_manager_.getChunk(group_,index);
                        {std::unique_lock<std::mutex> lock;
                            if(device_lock_)lock=std::unique_lock<std::mutex>(*device_lock_);
#ifdef FMQL_PROFILE
                            auto read_begin=fmql_profile::now_ns();
#endif
                            chunk.read(reinterpret_cast<char*>(data_.data()),0,data_.size());
#ifdef FMQL_PROFILE
                            p.ps_read_ms=fmql_profile::ms(fmql_profile::now_ns(),read_begin);
#endif
                        }
                        cv::Mat image(h_,w_,CV_8UC2,data_.data());
                        if(post_)post_(msg,image);
                        if(sink_.moveEnabled())sink_.submitOwned(data_);else sink_.submit(data_.data(),data_.size());
                    }
                }catch(...) {this->buffer_manager_.returnIndex(group_,index);throw;}
                this->buffer_manager_.returnIndex(group_,index);
#ifdef FMQL_PROFILE
                p.display_done_ns=fmql_profile::now_ns();
                p.display_work_ms=fmql_profile::ms(p.display_done_ns,p.display_dequeued_ns);
                p.e2e_ms=fmql_profile::ms(p.display_done_ns,p.capture_start_ns);
                fmql_profile::emit(p);
#endif
            }
        }catch(...) {error_=std::current_exception();failed_=true;}
    }
private:
    std::string group_;int w_,h_;Post post_;std::mutex* device_lock_;
    std::vector<uint8_t> data_;EthernetVideoSink sink_;
    std::exception_ptr error_;std::atomic<bool> failed_{false};
};
}
