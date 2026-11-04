#include "yolov8_plin_actor.hpp"
#include "yolov8_post.hpp"
#include "dfl_fused_cpu.hpp"
#include "pipeline/actor/sdicamera_input_actor.hpp"
#include "pipeline/io/input/sdicamera.hpp"
#include <yaml-cpp/yaml.h>
#include <iostream>
#include <csignal>

volatile std::sig_atomic_t running=1;
void signal_stop(int){running=0;}
int main(int argc,char**argv)try{
    if(argc!=6){std::cerr<<"Usage: an5641_pipeline_probe config capture|infer frames profile.csv read_ps_0_or_1\n";return 1;}
    auto config=YAML::LoadFile(argv[1]);std::string mode=argv[2];int limit=std::stoi(argv[3]);bool read_ps=std::stoi(argv[5]);
    if((mode!="capture"&&mode!="infer")||limit<2||limit>3000)throw std::runtime_error("Invalid mode/count");
    fmql_profile::open(argv[4]);fmql_profile::sample_period_us=100;fmql_profile::poll_sleep_us=fmql_profile::passive_overlap_enabled()?50:0;
    std::signal(SIGINT,signal_stop);std::signal(SIGTERM,signal_stop);
    auto device=icraft::xrt::Device::Open(config["sys"]["device"].as<std::string>());
    auto fpai_device=device.cast<fpai::FPAIDevice>();
    auto cam=config["pipeline"]["camera"],net=config["pipeline"]["icore"];
    if(cam["width"].as<int>()!=1920||cam["height"].as<int>()!=1080||cam["vtc"].as<bool>())throw std::runtime_error("Expected real1080p input");
    spdlog::set_level(spdlog::level::warn);
    {
        std::mutex io;
        BufferManager manager(4);
        ThreadSafeQueue<InputMessageForIcore> input(4);
        ThreadSafeQueue<IcoreMessageForPost> output(4);
        Yolov8PLinActor npu(fpai_device,manager,net["json"].as<std::string>(),net["raw"].as<std::string>(),"",&io);
        npu.bindInputQueue(&input);npu.bindOutputQueue(&output);
        auto camera=std::make_unique<fpai::SDICamera<fpai::FPAIDevice>>(0,fpai_device,1920,1080,camera_fmt::RGB565,
            1920,1080,camera_fmt::RGB565,crop_position::center,416,416,crop_position::center,0x40080000,false);
        fpai::SDICameraInputActor<fpai::FPAIDevice,fpai::FPAIBackend> capture(
            0,std::move(camera),fpai_device,manager,npu.sessions(),0x80000400,&io);
        capture.bindOutputQueue(&input);
        auto group=capture.getChunkGroupId();std::vector<char> pixels(1920*1080*2);
        int count=0,errors=0;uint64_t first=0,last=0;uint64_t first_sof=0,last_sof=0;
        if(mode=="infer")npu.start();capture.start();
        while(running&&count<limit){
            InputMessageForIcore captured;IcoreMessageForPost inferred;
            if(mode=="capture"){if(!input.wait_and_pop(captured))break;}
            else {if(!output.wait_and_pop(inferred))break;}
            auto&meta=mode=="capture"?captured.meta:inferred.meta;
            auto&p=meta.profile;
            if(meta.error_input||meta.invalid_ps_frame)++errors;
            if(read_ps){auto lock_begin=fmql_profile::now_ns();std::lock_guard<std::mutex> lock(io);auto begin=fmql_profile::now_ns();p.ps_lock_wait_ms=fmql_profile::ms(begin,lock_begin);
                manager.getChunk(group,meta.buffer_index).read(pixels.data(),0,pixels.size());
                p.ps_read_ms=fmql_profile::ms(fmql_profile::now_ns(),begin);}
            if(mode=="infer"&&!meta.error_input){
                auto begin=fmql_profile::now_ns();std::array<const float*,6> heads;
                for(int j=0;j<6;++j)heads[j]=reinterpret_cast<const float*>(inferred.icore_tensors[j].data().cptr());
                auto decoded=dfl_fused_cpu(heads,.25f,count+1).values;
                auto det=detect_yolov8(decoded,HardwareGeometry::center(1920,1080,416,416),.25f,.70f,&p);
                p.decode_ms=fmql_profile::ms(fmql_profile::now_ns(),begin);p.detections=det.size();
            }
            last=fmql_profile::now_ns();if(!count){first=last;first_sof=p.source_sof_after_capture;}
            last_sof=p.source_sof_after_capture;
            manager.returnIndex(group,meta.buffer_index);fmql_profile::emit(p);++count;
        }
        manager.stopRequests(group);capture.stop();if(mode=="infer"){npu.stop();npu.rethrow_failure();npu.verifySavedInputs();}
        std::cout<<"PROBE_RESULT mode="<<mode<<" read_ps="<<read_ps<<" frames="<<count<<" errors="<<errors
                 <<" elapsed_s="<<(last-first)/1e9<<" fps="<<(count>1?(count-1)*1e9/(last-first):0)
                 <<" source_sof_delta="<<(last_sof-first_sof)<<std::endl;
        if(errors||count<limit)throw std::runtime_error("Incomplete/error capture");
    }
    icraft::xrt::Device::Close(device);fmql_profile::output.close();return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<std::endl;return 2;}
