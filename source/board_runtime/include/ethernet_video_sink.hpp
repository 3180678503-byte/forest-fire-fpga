#pragma once
#include "rgb565_nv12.hpp"
#include <atomic>
#include <cstdlib>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <exception>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>
#include <string>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <fstream>
#include <algorithm>
extern char** environ;

namespace fmql_video {
struct VideoOptions {
    int width=1920,height=1080,fps=30,bitrate=6000000;
    size_t queue_frames=2;
    std::string url,log="ethernet_encoder.log",ffmpeg="/usr/bin/ffmpeg";
};

// Owns only the encoder child. All memory/network operations are outside device_io_mutex.
// Overload discards complete pending frames; partially written raw frames are never discarded.
class EthernetVideoSink {
public:
    explicit EthernetVideoSink(VideoOptions options):o_(std::move(options)) {
        if(o_.width<=0||o_.height<=0||o_.width%2||o_.height%2||o_.fps<1||o_.fps>60||
           o_.bitrate<100000||o_.bitrate>50000000||o_.queue_frames<1||o_.queue_frames>8)
            throw std::invalid_argument("Invalid Ethernet video dimensions/fps/bitrate/queue");
        // Production transport is UDP. Absolute .ts paths are permitted for diagnostic recording.
        if(o_.url.rfind("udp://",0)!=0 && (o_.url.empty()||o_.url.front()!='/'||
           o_.url.size()<3||o_.url.substr(o_.url.size()-3)!=".ts"))
            throw std::invalid_argument("video_url must be udp://host:port?... or absolute .ts path");
        const char* move=std::getenv("FMQL_ETH_MOVE");move_pool_=move&&std::string(move)=="1";
        if(move_pool_)for(size_t i=0;i<o_.queue_frames+1;++i)free_frames_.emplace_back(size_t(o_.width)*o_.height*2);
        launch();
        try {
#ifdef FMQL_ETH_PRIME
            primeEncoder();
#endif
            worker_=std::thread([this]{run();});}
        catch(...) {closeChild();throw;}
    }
    EthernetVideoSink(const EthernetVideoSink&)=delete;
    ~EthernetVideoSink(){try{finish();}catch(...) {}}
    void submit(const uint8_t* rgb565,size_t size) {
        if(size!=size_t(o_.width)*o_.height*2)throw std::invalid_argument("RGB565 frame size mismatch");
        rethrow_failure();
        std::vector<uint8_t> frame(rgb565,rgb565+size);
        if(move_pool_){submitOwned(frame);return;}
        {std::lock_guard<std::mutex> lock(mutex_);
            if(done_)throw std::runtime_error("Video output already stopped");
            ++submitted_;
            if(queue_.size()>=o_.queue_frames){queue_.pop_front();++dropped_;}
            queue_.push_back(std::move(frame));
        }
        cv_.notify_one();
    }
    bool moveEnabled()const{return move_pool_;}
    void submitOwned(std::vector<uint8_t>& frame){
        if(!move_pool_||frame.size()!=size_t(o_.width)*o_.height*2)throw std::invalid_argument("Invalid owned frame");
        rethrow_failure();std::vector<uint8_t> reusable;
        {std::lock_guard<std::mutex> lock(mutex_);
            if(done_)throw std::runtime_error("Video output already stopped");
            if(queue_.size()>=o_.queue_frames){reusable=std::move(queue_.front());queue_.pop_front();++dropped_;}
            else if(!free_frames_.empty()){reusable=std::move(free_frames_.back());free_frames_.pop_back();}
            if(reusable.empty())reusable.resize(size_t(o_.width)*o_.height*2);
            queue_.push_back(std::move(frame));frame=std::move(reusable);++submitted_;
        }
        cv_.notify_one();
    }
    bool failed()const{return failed_.load();}
    void rethrow_failure() {
        if(!failed())return;
        std::lock_guard<std::mutex> lock(mutex_);if(error_)std::rethrow_exception(error_);
    }
    void finish() {
        {std::lock_guard<std::mutex> lock(mutex_);done_=true;}cv_.notify_all();
        if(worker_.joinable())worker_.join();
        closeChild();rethrow_failure();
    }
private:
    using Clock=std::chrono::steady_clock;
#ifdef FMQL_ETH_PRIME
    void primeEncoder() {
        struct PipeSignalGuard {
            sigset_t blocked,previous;
            PipeSignalGuard(){sigemptyset(&blocked);sigaddset(&blocked,SIGPIPE);pthread_sigmask(SIG_BLOCK,&blocked,&previous);}
            ~PipeSignalGuard(){
                if(!sigismember(&previous,SIGPIPE)){timespec zero{};while(sigtimedwait(&blocked,nullptr,&zero)==SIGPIPE){}}
                pthread_sigmask(SIG_SETMASK,&previous,nullptr);
            }
        } signal_guard;
        const char* option=std::getenv("FMQL_ENCODER_PRIME");
        if(option&&std::string(option)=="0"){std::cerr<<"[ENCODER_READY] priming_disabled=1\n";return;}
        std::vector<uint8_t> black(size_t(o_.width)*o_.height*3/2,128);
        std::fill(black.begin(),black.begin()+size_t(o_.width)*o_.height,16);
        auto start=Clock::now();
        for(unsigned n=0;n<128;++n){
            writeFrame(black.data(),black.size());++primed_;
            std::ifstream report(o_.log+".progress");std::string line;long frames=0,bytes=0;
            while(std::getline(report,line)){
                if(line.rfind("frame=",0)==0)frames=std::strtol(line.c_str()+6,nullptr,10);
                if(line.rfind("total_size=",0)==0)bytes=std::strtol(line.c_str()+11,nullptr,10);
            }
            if(frames>0&&bytes>0){
                std::cerr<<"[ENCODER_READY] primed_frames="<<primed_<<" encoded_frames="<<frames
                         <<" muxed_bytes="<<bytes<<" elapsed_ms="<<std::chrono::duration<double,std::milli>(Clock::now()-start).count()<<std::endl;
                return;
            }
            if(Clock::now()-start>std::chrono::seconds(5))break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        throw std::runtime_error("VPU did not report encoded output during pre-capture priming");
    }
#endif
    void launch() {
        int fds[2];if(pipe2(fds,O_CLOEXEC)<0)throw std::runtime_error("encoder pipe failed");
        int logfd=open(o_.log.c_str(),O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC,0644);
        if(logfd<0){close(fds[0]);close(fds[1]);throw std::runtime_error("Cannot open encoder log");}
#ifdef FMQL_ETH_PRIME
        int progressfd=open((o_.log+".progress").c_str(),O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC|O_NOFOLLOW,0644);
        if(progressfd<0){close(fds[0]);close(fds[1]);close(logfd);throw std::runtime_error("Cannot reset encoder readiness log");}
        close(progressfd);
#endif
        std::vector<std::string> args={o_.ffmpeg,"-hide_banner","-loglevel","warning","-nostdin","-y",
#ifdef FMQL_ETH_PRIME
            "-progress",o_.log+".progress",
#endif
            "-f","rawvideo","-pixel_format","nv12","-video_size",std::to_string(o_.width)+"x"+std::to_string(o_.height),
            "-framerate",std::to_string(o_.fps),"-use_wallclock_as_timestamps","1","-i","pipe:0",
            // Ubuntu FFmpeg 4.2/mvx crashes on a directly demuxed NV12 AVFrame.
            // Repacking through planar YUV allocates a driver-compatible frame.
            "-an","-vf","format=yuv420p,format=nv12","-c:v","h264_v4l2m2m","-b:v",std::to_string(o_.bitrate),"-bf","0",
#ifdef FMQL_ETH_REPEAT_HEADERS
            "-bsf:v","extract_extradata,dump_extra=freq=keyframe",
#endif
            "-vsync","0","-f","mpegts","-muxdelay","0","-muxpreload","0",
            "-mpegts_flags","+resend_headers","-flush_packets","1",o_.url};
        std::vector<char*> av;for(auto& a:args)av.push_back(a.data());av.push_back(nullptr);
        posix_spawn_file_actions_t actions;posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions,fds[0],STDIN_FILENO);
        posix_spawn_file_actions_adddup2(&actions,logfd,STDERR_FILENO);
        posix_spawn_file_actions_adddup2(&actions,logfd,STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&actions,fds[0]);
        posix_spawn_file_actions_addclose(&actions,fds[1]);
        posix_spawn_file_actions_addclose(&actions,logfd);
        posix_spawnattr_t attr;posix_spawnattr_init(&attr);
        sigset_t def,mask;sigemptyset(&def);sigaddset(&def,SIGINT);sigaddset(&def,SIGTERM);sigaddset(&def,SIGPIPE);sigemptyset(&mask);
        posix_spawnattr_setsigdefault(&attr,&def);posix_spawnattr_setsigmask(&attr,&mask);
        posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETSIGDEF|POSIX_SPAWN_SETSIGMASK);
        int result=posix_spawn(&child_,o_.ffmpeg.c_str(),&actions,&attr,av.data(),environ);
        posix_spawnattr_destroy(&attr);posix_spawn_file_actions_destroy(&actions);
        close(fds[0]);close(logfd);
        if(result){close(fds[1]);child_=-1;throw std::runtime_error(std::string("Cannot start ffmpeg: ")+strerror(result));}
        fd_=fds[1];fcntl(fd_,F_SETFL,fcntl(fd_,F_GETFL)|O_NONBLOCK);
    }
    void writeFrame(const uint8_t* p,size_t n) {
        auto deadline=Clock::now()+std::chrono::seconds(5);
        while(n) {
            if(Clock::now()>deadline)throw std::runtime_error("VPU raw input blocked >5s; see encoder log");
            pollfd item{fd_,POLLOUT,0};int ready=poll(&item,1,100);
            if(ready<0&&errno==EINTR)continue;
            if(ready<0||item.revents&(POLLERR|POLLHUP|POLLNVAL))throw std::runtime_error("VPU encoder closed input; see encoder log");
            if(!ready)continue;
            auto bytes=write(fd_,p,n);
            if(bytes<0){if(errno==EINTR||errno==EAGAIN)continue;throw std::runtime_error("VPU input write failed");}
            if(bytes==0)throw std::runtime_error("VPU input made no progress");
            p+=bytes;n-=bytes;
        }
    }
    void run() noexcept {
        // A broken encoder pipe becomes an ordinary worker exception, not process termination.
        sigset_t set;sigemptyset(&set);sigaddset(&set,SIGPIPE);pthread_sigmask(SIG_BLOCK,&set,nullptr);
        auto start=Clock::now();double convert_sum=0,write_sum=0;
        try {
            std::vector<uint8_t> nv12(size_t(o_.width)*o_.height*3/2);
            while(true) {
                std::vector<uint8_t> frame;
                {std::unique_lock<std::mutex> lock(mutex_);cv_.wait(lock,[&]{return done_||!queue_.empty();});
                    if(queue_.empty()&&done_)break;
                    frame=std::move(queue_.front());queue_.pop_front();}
                auto a=Clock::now();rgb565_nv12(frame.data(),size_t(o_.width)*2,nv12.data(),o_.width,o_.height);
                auto b=Clock::now();writeFrame(nv12.data(),nv12.size());auto c=Clock::now();++written_;
                convert_sum+=std::chrono::duration<double,std::milli>(b-a).count();
                write_sum+=std::chrono::duration<double,std::milli>(c-b).count();
                if(move_pool_){std::lock_guard<std::mutex> lock(mutex_);free_frames_.push_back(std::move(frame));}
            }
        }catch(...) {
            {std::lock_guard<std::mutex> lock(mutex_);error_=std::current_exception();queue_.clear();}
            failed_=true;
        }
        double elapsed=std::chrono::duration<double>(Clock::now()-start).count();
        std::cerr<<"[ETH_OUTPUT] submitted="<<submitted_<<" written="<<written_<<" dropped="<<dropped_<<" primed="<<primed_
                 <<" elapsed_s="<<elapsed<<" encoder_input_fps="<<(elapsed>0?written_/elapsed:0)
                 <<" rgb565_nv12_mean_ms="<<(written_?convert_sum/written_:0)
                 <<" pipe_write_mean_ms="<<(written_?write_sum/written_:0)<<std::endl;
    }
    void closeChild() {
        if(fd_>=0){close(fd_);fd_=-1;}
        if(child_<=0)return;
        int status=0;bool reaped=false;
        auto waitFor=[&](int milliseconds) {
            auto end=Clock::now()+std::chrono::milliseconds(milliseconds);
            do {auto r=waitpid(child_,&status,WNOHANG);
                if(r==child_||(r<0&&errno==ECHILD)){reaped=true;return;}
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }while(Clock::now()<end);
        };
        waitFor(5000);
        bool forced=false;
        if(!reaped){forced=true;kill(child_,SIGTERM);waitFor(1000);}
        if(!reaped){kill(child_,SIGKILL);while(waitpid(child_,&status,0)<0&&errno==EINTR){};}
        child_=-1;
        if(forced||!WIFEXITED(status)||WEXITSTATUS(status)!=0) {
            {std::lock_guard<std::mutex> lock(mutex_);
                if(!error_)error_=std::make_exception_ptr(std::runtime_error("VPU encoder exited abnormally; see "+o_.log));}
            failed_=true;
        }
    }
    VideoOptions o_;int fd_=-1;pid_t child_=-1;
    std::thread worker_;std::mutex mutex_;std::condition_variable cv_;
    std::deque<std::vector<uint8_t>> queue_;std::vector<std::vector<uint8_t>> free_frames_;bool move_pool_=false;bool done_=false;
    std::exception_ptr error_;std::atomic<bool> failed_{false};
    std::atomic<uint64_t> submitted_{0},dropped_{0};uint64_t written_=0;unsigned primed_=0;
};
}
