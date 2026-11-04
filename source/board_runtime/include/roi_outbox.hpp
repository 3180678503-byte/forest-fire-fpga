#pragma once
#include "roi_event_gate.hpp"
#include <opencv2/opencv.hpp>
#include <yaml-cpp/yaml.h>
#include <spdlog/spdlog.h>
#include <filesystem>
#include <fstream>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <atomic>
#include <iomanip>
#include <chrono>
#include <ctime>

inline std::string roi_request_stem(uint64_t event,uint64_t frame){
    return "event_"+std::to_string(event)+"_frame_"+std::to_string(frame);
}

class RoiOutbox {
    using Clock=std::chrono::steady_clock;
    struct Job {RoiGateDecision decision;cv::Mat image;cv::Rect rect;int width,height;uint64_t captured_ns;};
    struct Pending {std::string stem;uint64_t event,frame;Clock::time_point published;};
public:
    struct Summary {uint64_t event=0,frame=0;std::string text="QWEN idle";bool stale=false;};
private:
    std::filesystem::path root_;
    std::thread worker_;std::mutex mutex_;std::condition_variable condition_;
    std::deque<Job> jobs_;std::vector<Pending> pending_;
    bool stop_=false;size_t budget_,submitted_=0;
    std::atomic<bool> outstanding_{false};
    std::atomic<int> failures_{0};
    std::atomic<uint64_t> next_allowed_ns_{0};
    uint64_t cooldown_ns_=0;
    Summary summary_;

    static bool valid_enum(const std::string& v,const std::initializer_list<const char*>& values){
        return std::any_of(values.begin(),values.end(),[&](auto item){return v==item;});
    }
    void update(uint64_t event,uint64_t frame,const std::string& text,bool stale=false){
        std::lock_guard<std::mutex> lock(mutex_);summary_={event,frame,text,stale};
    }
    void poll_reviews(){
        for(auto it=pending_.begin();it!=pending_.end();){
            auto file=root_/"reviews"/(it->stem+".json");
            if(!std::filesystem::exists(file)){
                if(Clock::now()-it->published<std::chrono::seconds(20)){++it;continue;}
                spdlog::info("[QWEN_REVIEW] event={} frame={} status=fallback reason=worker_timeout advisory_only=true",it->event,it->frame);
                update(it->event,it->frame,"QWEN unavailable");
            }else try{
                if(std::filesystem::file_size(file)>65536)throw std::runtime_error("Oversized review");
                auto reply=YAML::LoadFile(file.string());
                if(reply["event_id"].as<uint64_t>()!=it->event||reply["frame"].as<uint64_t>()!=it->frame)
                    throw std::runtime_error("Review identity mismatch");
                auto semantic=reply["semantic"];
                if(!semantic.IsMap()||semantic.size()!=4)throw std::runtime_error("Semantic fields");
                auto verdict=semantic["verdict"].as<std::string>(),reason=semantic["reason_code"].as<std::string>();
                auto evidence=semantic["evidence"].as<std::string>();float confidence=semantic["confidence"].as<float>();
                if(!valid_enum(verdict,{"CONFIRM","REJECT","UNCERTAIN"})||!valid_enum(reason,{"FLAME","SMOKE","FOG","REFLECTION","UNKNOWN"})||
                   !std::isfinite(confidence)||confidence<0||confidence>1||evidence.size()>2048)throw std::runtime_error("Semantic values");
                std::string backend=reply["backend"].as<std::string>(),status=reply["status"].as<std::string>();
                bool stale=status=="stale";
                if(stale)update(it->event,it->frame,"QWEN expired",true);
                else update(it->event,it->frame,"QWEN "+std::string(backend=="mock"?"MOCK ":"")+verdict+"/"+reason);
                spdlog::info("[QWEN_REVIEW] event={} frame={} backend={} status={} verdict={} reason={} confidence={} advisory_only=true",
                             it->event,it->frame,backend,status,verdict,reason,confidence);
            }catch(const std::exception&){
                // An unavailable semantic result never aborts local inference.
                update(it->event,it->frame,"QWEN unavailable");
                spdlog::info("[QWEN_REVIEW] event={} frame={} status=fallback reason=invalid_reply advisory_only=true",it->event,it->frame);
            }
            it=pending_.erase(it);
            next_allowed_ns_=uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count())+cooldown_ns_;
            outstanding_=false;
        }
    }
    void run(){
        for(;;){
            Job job;bool have=false;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                condition_.wait_for(lock,std::chrono::milliseconds(100),[&]{return stop_||!jobs_.empty();});
                if(!jobs_.empty()){job=std::move(jobs_.front());jobs_.pop_front();have=true;}
                else if(stop_)break;
            }
            if(have)try{
                const auto& d=job.decision;auto stem=roi_request_stem(d.event,d.frame);
                if(std::max(job.image.cols,job.image.rows)>640){double scale=640.0/std::max(job.image.cols,job.image.rows);cv::resize(job.image,job.image,{},scale,scale,cv::INTER_AREA);}
                auto temporary=root_/"requests"/(stem+".tmp.jpg"),image=root_/"requests"/(stem+".jpg");
                std::vector<unsigned char> encoded;int quality=85;
                for(;;){
                    if(!cv::imencode(".jpg",job.image,encoded,{cv::IMWRITE_JPEG_QUALITY,quality}))throw std::runtime_error("JPEG encode");
                    if(encoded.size()<=128*1024)break;
                    if(quality>45){quality-=10;continue;}
                    if(std::max(job.image.cols,job.image.rows)<=160)throw std::runtime_error("JPEG size");
                    cv::resize(job.image,job.image,{},.8,.8,cv::INTER_AREA);quality=75;
                }
                std::ofstream jpeg(temporary,std::ios::binary);
                jpeg.write(reinterpret_cast<const char*>(encoded.data()),encoded.size());jpeg.close();
                if(!jpeg)throw std::runtime_error("JPEG write");
                std::filesystem::rename(temporary,image);
                auto now=std::time(nullptr);std::tm utc{};gmtime_r(&now,&utc);char stamp[40];std::strftime(stamp,sizeof(stamp),"%Y-%m-%dT%H:%M:%SZ",&utc);
                std::ofstream meta(root_/"requests"/(stem+".tmp"));meta<<std::setprecision(9);
                meta<<"{\"schema_version\":1,\"frame\":"<<d.frame<<",\"event_id\":"<<d.event
                    <<",\"gate_backend\":\"software_reference\",\"image_file\":\""<<image.filename().string()
                    <<"\",\"target_class\":\""<<(d.detection.category==0?"fire":"smoke")<<"\",\"source_width\":"<<job.width<<",\"source_height\":"<<job.height
                    <<",\"crop\":["<<job.rect.x<<','<<job.rect.y<<','<<job.rect.width<<','<<job.rect.height<<"]"
                    <<",\"bbox_xyxy\":["<<d.detection.box.x<<','<<d.detection.box.y<<','<<d.detection.box.x+d.detection.box.width<<','<<d.detection.box.y+d.detection.box.height<<"]"
                    <<",\"capture_monotonic_ns\":"<<job.captured_ns<<",\"timestamp_utc\":\""<<stamp<<"\",\"decision\":{\"class_id\":"<<d.detection.category
                    <<",\"confidence\":"<<d.detection.score<<",\"consecutive_hits\":"<<d.consecutive_hits<<",\"confirmed\":"<<(d.confirmed?"true":"false")
                    <<",\"need_qwen\":"<<(d.gate.need_qwen?"true":"false")<<"}}\n";meta.close();
                if(!meta)throw std::runtime_error("Metadata write");
                std::filesystem::rename(root_/"requests"/(stem+".tmp"),root_/"requests"/(stem+".json"));
                pending_.push_back({stem,d.event,d.frame,Clock::now()});
                update(d.event,d.frame,"QWEN pending");
                spdlog::info("[QWEN_OUTBOX] published event={} frame={} crop={}x{}",d.event,d.frame,job.image.cols,job.image.rows);
            }catch(const std::exception&){++failures_;outstanding_=false;spdlog::warn("[QWEN_OUTBOX] publication failed; local inference continues");}
            poll_reviews();
        }
        poll_reviews();
    }
public:
    RoiOutbox(const std::string& directory,size_t capacity=1,size_t budget=8,double cooldown_seconds=10):root_(directory),budget_(budget){
        if(capacity!=1||budget>1000000||!std::isfinite(cooldown_seconds)||cooldown_seconds<0||cooldown_seconds>3600)
            throw std::invalid_argument("Invalid request limits");
        cooldown_ns_=uint64_t(cooldown_seconds*1e9);
        std::filesystem::create_directories(root_/"requests");std::filesystem::create_directories(root_/"reviews");
        if(!std::filesystem::is_empty(root_/"requests"))throw std::runtime_error("Use a fresh ROI output directory");
        worker_=std::thread(&RoiOutbox::run,this);
    }
    ~RoiOutbox(){finish();}
    void finish(){
        {std::lock_guard<std::mutex> lock(mutex_);stop_=true;}
        condition_.notify_one();if(worker_.joinable())worker_.join();
    }
    bool submit(const RoiGateDecision& d,const cv::Mat& bgr){
        if(!d.request_eligible)return false;
        std::lock_guard<std::mutex> lock(mutex_);
        auto now_ns=uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count());
        if(stop_||outstanding_||(budget_&&submitted_>=budget_)||now_ns<next_allowed_ns_)return false;
        float px=std::max(8.f,d.detection.box.width*.2f),py=std::max(8.f,d.detection.box.height*.2f);
        int x=std::max(0,int(std::floor(d.detection.box.x-px))),y=std::max(0,int(std::floor(d.detection.box.y-py)));
        int right=std::min(bgr.cols,int(std::ceil(d.detection.box.x+d.detection.box.width+px)));
        int bottom=std::min(bgr.rows,int(std::ceil(d.detection.box.y+d.detection.box.height+py)));
        if(right<=x||bottom<=y)return false;
        cv::Rect rect(x,y,right-x,bottom-y);
        auto captured=std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();
        cv::Mat crop;
        if(bgr.type()==CV_8UC2)cv::cvtColor(bgr(rect),crop,cv::COLOR_BGR5652BGR);
        else crop=bgr(rect).clone();
        jobs_.push_back({d,std::move(crop),rect,bgr.cols,bgr.rows,uint64_t(captured)});
        outstanding_=true;++submitted_;condition_.notify_one();return true;
    }
    bool pending()const{return outstanding_.load();}
    Summary summary(){std::lock_guard<std::mutex> lock(mutex_);return summary_;}
    int failures()const{return failures_.load();}
};
