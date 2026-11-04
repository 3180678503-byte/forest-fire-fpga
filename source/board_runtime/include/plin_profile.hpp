#pragma once
// Only the diagnostic target includes this header. One record follows a frame
// through the unchanged PLIN pipeline and is written by the display thread.
#include <chrono>
#include <cstdint>
#include <fstream>
#include <mutex>
#include <cstdlib>
#include <stdexcept>

namespace fmql_profile {
using Clock=std::chrono::steady_clock;
inline uint64_t now_ns(){return std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();}
inline double ms(uint64_t end,uint64_t start){return double(end-start)/1e6;}
#define FMQL_PROFILE_FIELDS(X) \
 X(passive_wait_ms) X(ps_lock_wait_ms) X(source_sof_at_trigger) X(source_sof_after_capture) X(source_eof_after_capture) X(hw_done_to_fetch_cycles) X(hw_fetch_count) \
 X(frame) X(buffer) X(capture_start_ns) X(trigger_ns) X(imk_done_ns) X(capture_done_ns) X(capture_enqueued_ns) \
 X(npu_dequeued_ns) X(npu_lock_ns) X(npu_done_ns) X(npu_enqueued_ns) X(display_dequeued_ns) X(display_done_ns) \
 X(buffer_wait_ms) X(camera_lock_wait_ms) X(imk_config_ms) X(camera_trigger_ms) X(imk_poll_ms) X(imk_cleanup_ms) \
 X(tensor_bind_ms) X(ps_wait_ms) X(capture_lock_ms) X(imk_first_pixel_ms) X(imk_input_full_ms) X(imk_stream_ms) X(imk_tail_ms) \
 X(imk_initial_count) X(imk_final_count) X(imk_cycles) X(imk_polls) X(imk_samples) \
 X(npu_queue_wait_ms) X(npu_lock_wait_ms) X(npu_forward_call_ms) X(npu_ready_ms) X(npu_download_ms) X(npu_reset_ms) X(npu_lock_ms) X(npu_hash_ms) \
 X(display_queue_wait_ms) X(ps_read_ms) X(decode_ms) X(confidence_filter_ms) X(sort_ms) X(nms_ms) X(box_restore_ms) \
 X(rgb565_to_bgr_ms) X(draw_ms) X(bgr_to_rgb565_ms) X(hdmi_submit_ms) X(buffer_return_ms) X(display_work_ms) X(e2e_ms) X(detections)
struct Frame {
// Integers up to nanosecond timestamps are kept exact separately below in the
// CSV (steady-clock uptime is well below the exact-integer limit of double).
#define FIELD(name) double name=0;
    FMQL_PROFILE_FIELDS(FIELD)
#undef FIELD
    Frame(){imk_first_pixel_ms=imk_input_full_ms=imk_stream_ms=imk_tail_ms=-1;}
};
inline thread_local Frame* imagemake_frame=nullptr;
inline thread_local std::mutex* passive_io_mutex=nullptr;
inline bool passive_overlap_enabled(){const char* p=std::getenv("FMQL_PASSIVE_CAPTURE");return p&&std::string(p)=="1";}
class PassiveCaptureScope {
    std::unique_lock<std::mutex>& lock_;Frame* frame_;uint64_t start_=0;bool active_;
public:
    PassiveCaptureScope(std::unique_lock<std::mutex>& lock,std::mutex* mutex,Frame& frame)
        :lock_(lock),frame_(&frame),active_(passive_overlap_enabled()&&mutex&&lock.owns_lock()) {
        if(active_){passive_io_mutex=mutex;start_=now_ns();lock_.unlock();}
    }
    ~PassiveCaptureScope(){if(active_){passive_io_mutex=nullptr;lock_.lock();frame_->passive_wait_ms=ms(now_ns(),start_);}}
};

inline int poll_sleep_us=0;
inline int sample_period_us=100;
inline std::ofstream output;
inline void open(const std::string& path){
    output.open(path);if(!output)throw std::runtime_error("Cannot create profile CSV: "+path);
    bool first=true;
#define HEADER(name) if(!first)output<<',';first=false;output<<#name;
    FMQL_PROFILE_FIELDS(HEADER)
#undef HEADER
    output<<'\n';output.precision(17);
}
inline void emit(const Frame& frame){
    bool first=true;
#define VALUE(name) if(!first)output<<',';first=false;output<<frame.name;
    FMQL_PROFILE_FIELDS(VALUE)
#undef VALUE
    output<<'\n';if(!output)throw std::runtime_error("Profile CSV write failed");
}
// A guard also clears the pointer if the vendor timeout throws.
struct ImageMakeScope {
    explicit ImageMakeScope(Frame& frame){imagemake_frame=&frame;}
    ~ImageMakeScope(){imagemake_frame=nullptr;}
};
}
