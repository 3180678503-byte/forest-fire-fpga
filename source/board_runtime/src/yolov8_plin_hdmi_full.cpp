// Based on the vendor PLin+SingleNet+HDMI example. No CPU preprocessing
// on the inference input: ImageMake writes the NPU input PLDDR directly.
#include "yolov8_plin_actor.hpp"
#include "yolov8_post.hpp"
#include "roi_outbox.hpp"
#include "dfl_fused_cpu.hpp"
#include "roi_render.hpp"
#include "action_shadow_bridge.hpp"
#include "pipeline/actor/sdicamera_input_actor.hpp"
#include "hdmi_output_actor.hpp"
#include "pipeline/io/input/sdicamera.hpp"
#include "pipeline/memory/buffer_manager.hpp"
#include <yaml-cpp/yaml.h>
#include <csignal>
#include <iostream>
#include <thread>

volatile std::sig_atomic_t keep_running=1;
void stop_signal(int){keep_running=0;}

int main(int argc,char** argv)try {
    if(argc<2){std::cerr<<"Usage: yolo_qwen_esp32_hdmi configs/live.yaml [--frames N] [--buffers 1..4] [--dump directory]\n";return 1;}
    uint64_t frame_limit=0;
    size_t buffers=4;std::string dump_directory,roi_directory;
#ifdef FMQL_PROFILE
    std::string profile_path="profile.csv";
#endif
    for(int i=2;i<argc;++i){
        std::string flag=argv[i];if(i+1>=argc)throw std::runtime_error("Missing argument value");
#ifdef FMQL_PROFILE
        if(flag=="--profile-out"){profile_path=argv[++i];continue;}
        if(flag=="--profile-poll-us" || flag=="--profile-sample-us"){
            auto value=std::stoll(argv[++i]);
            if(value<0||value>10000)throw std::runtime_error("Profile interval must be 0..10000 us");
            if(flag=="--profile-poll-us")fmql_profile::poll_sleep_us=int(value);
            else fmql_profile::sample_period_us=int(value);
            continue;
        }
#endif
        if(flag=="--roi-output"){roi_directory=argv[++i];continue;}
        if(flag=="--dump"){dump_directory=argv[++i];continue;}
        auto n=std::stoll(argv[++i]);if(n<=0)throw std::runtime_error("Count must be positive");
        if(flag=="--frames")frame_limit=static_cast<uint64_t>(n);
        else if(flag=="--buffers"&&n<=4)buffers=static_cast<size_t>(n);
        else throw std::runtime_error("Expected --frames N, --buffers 1..4 or --dump directory");
    }
#ifdef FMQL_PROFILE
    fmql_profile::open(profile_path);
#endif
    auto config=YAML::LoadFile(argv[1]);
    auto system=config["sys"],cam=config["pipeline"]["camera"],net=config["pipeline"]["icore"];
    int width=cam["width"].as<int>(),height=cam["height"].as<int>();
    int net_w=net["net_w"].as<int>(),net_h=net["net_h"].as<int>();
    if(width!=1920||height!=1080||net_w!=416||net_h!=416)
        throw std::runtime_error("This build supports 1080P PL camera -> 416x416 YOLOv8 only");
    const auto geometry=HardwareGeometry::center(width,height,net_w,net_h);
    float confidence=net["conf"].as<float>(),iou=net["iou_thresh"].as<float>();
    if(confidence<0||confidence>1||iou<0||iou>1)throw std::runtime_error("Invalid thresholds");
    spdlog::set_level(spdlog::level::info);
    spdlog::info("PLIN: camera -> PL resize -> ImageMake -> NPU input PLDDR; no CPU letterbox");
    spdlog::info("Hardware crop: x={},y={},w={},h={}, stride_x={},stride_y={}",geometry.bias_x,geometry.bias_y,
                 net_w*geometry.stride_x,net_h*geometry.stride_y,geometry.stride_x,geometry.stride_y);
    auto device=icraft::xrt::Device::Open(system["device"].as<std::string>());
    auto fpai_device=device.cast<fpai::FPAIDevice>();
    // The actors and all Session/memory owners are destroyed before Device::Close.
    {
        spdlog::info("Pipeline buffers={}",buffers);
        std::mutex device_io_mutex;
        spdlog::info("Capture/ImageMake, NPU and HDMI I/O share one mutex; ROI/network remain asynchronous");
        BufferManager manager(buffers);
        ThreadSafeQueue<InputMessageForIcore> camera_to_npu(buffers);
        ThreadSafeQueue<IcoreMessageForPost> npu_to_display(buffers);
        Yolov8PLinActor npu(fpai_device,manager,net["json"].as<std::string>(),net["raw"].as<std::string>(),dump_directory,&device_io_mutex);
        npu.bindInputQueue(&camera_to_npu);npu.bindOutputQueue(&npu_to_display);
        auto camera=std::make_unique<fpai::SDICamera<fpai::FPAIDevice>>(
            0,fpai_device,width,height,camera_fmt::RGB565,
            width,height,camera_fmt::RGB565,crop_position::center,
            net_w,net_h,crop_position::center,0x40080000,cam["vtc"].as<bool>());
        fpai::SDICameraInputActor<fpai::FPAIDevice,fpai::FPAIBackend> camera_actor(
            0,std::move(camera),fpai_device,manager,npu.sessions(),0x80000400,&device_io_mutex);
        camera_actor.bindOutputQueue(&camera_to_npu);
        std::array<const char*,2> labels={"fire","smoke"};
        RoiEventGate roi_gate(5,10,16,.30f);
        std::unique_ptr<RoiOutbox> outbox;
        auto qwen=config["pipeline"]["qwen"];
        size_t review_budget=qwen&&qwen["max_jobs"]?qwen["max_jobs"].as<size_t>():8;
        double review_cooldown=qwen&&qwen["cooldown_s"]?qwen["cooldown_s"].as<double>():10;
        if(!roi_directory.empty())outbox=std::make_unique<RoiOutbox>(roi_directory,1,review_budget,review_cooldown);
        spdlog::info("[QWEN_CONFIG] enabled={} max_jobs={} cooldown_s={} transport=loopback_esp32 advisory_only=true",
                     !roi_directory.empty(),review_budget,review_cooldown);
        std::atomic<uint64_t> frames{0};
        auto previous_frame=std::chrono::steady_clock::now();
        auto first_frame=previous_frame;
        ActionShadowBridge action_shadow;
        auto post=[&](const IcoreMessageForPost& message,cv::Mat& rgb565){
            if(message.icore_tensors.size()!=6)throw std::runtime_error("Missing YOLOv8 heads");
            auto start=std::chrono::steady_clock::now();
            std::array<const float*,6> heads;
            for(int i=0;i<6;++i)heads[i]=reinterpret_cast<const float*>(message.icore_tensors[i].data().cptr());
#ifdef FMQL_PROFILE
            auto &p=message.meta.profile;
            auto decode_start=fmql_profile::now_ns();
#endif
            auto decoded=dfl_fused_cpu(heads,confidence,frames.load()+1).values;
#ifdef FMQL_PROFILE
            p.decode_ms=fmql_profile::ms(fmql_profile::now_ns(),decode_start);
#endif
            auto detections=detect_yolov8(decoded,geometry,confidence,iou
#ifdef FMQL_PROFILE
                                         ,&p
#endif
                                         );
            auto action_text=action_shadow.update(detections,width,height,frames.load()+1);
#ifdef FMQL_PROFILE
            p.detections=detections.size();
#endif
            auto post_end=std::chrono::steady_clock::now();
            // PS camera frame is read only for rendering, never for model input.
#ifdef FMQL_PROFILE
            auto convert_start=fmql_profile::now_ns();
#endif
            if(!dump_directory.empty()&&frames.load()==0){
                cv::Mat image;cv::cvtColor(rgb565,image,cv::COLOR_BGR5652BGR);
                std::filesystem::create_directories(dump_directory);cv::imwrite(dump_directory+"/camera_first.png",image);
            }
            std::string review_text;
            if(outbox){
                auto decisions=roi_gate.process(detections,width,height,frames.load()+1);
                for(auto& decision:decisions)if(outbox->submit(decision,rgb565))roi_gate.mark_requested(decision.event);
                auto review=outbox->summary();
                bool current=std::any_of(decisions.begin(),decisions.end(),[&](const auto& d){return d.event&&d.event==review.event;});
                if(current&&!review.stale)review_text=review.text;
            }
            auto now=std::chrono::steady_clock::now();
            double interval=std::chrono::duration<double>(now-previous_frame).count();previous_frame=now;
            auto count=++frames;if(count==1)first_frame=now;
            optimized_render::overlay(rgb565,detections,labels,count,interval>0?1/interval:0,true);
            if(!action_text.empty()){
                cv::Rect bounds(10,78,std::min(1400,rgb565.cols-10),40);cv::Mat patch;
                cv::cvtColor(rgb565(bounds),patch,cv::COLOR_BGR5652BGR);
                cv::putText(patch,action_text,{5,26},cv::FONT_HERSHEY_SIMPLEX,.6,{255,255,0},1);
                cv::cvtColor(patch,rgb565(bounds),cv::COLOR_BGR2BGR565);
            }
            if(!review_text.empty()){
                cv::Rect bounds(10,42,std::min(1200,rgb565.cols-10),40);cv::Mat patch;
                cv::cvtColor(rgb565(bounds),patch,cv::COLOR_BGR5652BGR);
                cv::putText(patch,review_text,{5,26},cv::FONT_HERSHEY_SIMPLEX,.6,{0,255,255},1);
                cv::cvtColor(patch,rgb565(bounds),cv::COLOR_BGR2BGR565);
            }
            double post_ms=std::chrono::duration<double,std::milli>(post_end-start).count();
            double display_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-post_end).count();
            spdlog::info("[YOLOv8][frame={}] dfl_sigmoid_nms_ms={:.3f}, convert_draw_ms={:.3f}, detections={}",
                         count,post_ms,display_ms,detections.size());
            if(count>1){
                double seconds=std::chrono::duration<double>(now-first_frame).count();
                spdlog::info("[THROUGHPUT] frames={}, elapsed_since_first_s={:.6f}, fps={:.3f}",
                             count,seconds,(count-1)/seconds);
            }
            if(frame_limit&&count>=frame_limit)keep_running=0;
        };
        fmql_video::HDMIOutputActor<IcoreMessageForPost> display_actor(
            manager,camera_actor.getChunkGroupId(),fpai_device,width,height,post,&device_io_mutex);
        display_actor.bindInputQueue(&npu_to_display);
        std::signal(SIGINT,stop_signal);std::signal(SIGTERM,stop_signal);
        display_actor.start();npu.start();camera_actor.start();
        spdlog::info("Actors started. Stop with Ctrl+C.");
        while(keep_running&&!npu.failed()&&!display_actor.failed())std::this_thread::sleep_for(std::chrono::milliseconds(100));
        // Wake buffer-index waiters without issuing duplicate frame indices.
        manager.stopRequests(camera_actor.getChunkGroupId());
        camera_actor.stop();npu.stop();display_actor.stop();
        display_actor.finish();
        npu.rethrow_failure();
        npu.verifySavedInputs();
        if(outbox)outbox->finish();
    }
    icraft::xrt::Device::Close(device);
#ifdef FMQL_PROFILE
    fmql_profile::output.close();
#endif
    return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<std::endl;return 2;}
