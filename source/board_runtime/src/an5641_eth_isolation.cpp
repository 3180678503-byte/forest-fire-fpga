#include "yolov8_plin_actor.hpp"
#include "ethernet_video_sink.hpp"
#include <yaml-cpp/yaml.h>
#include <atomic>
#include <csignal>
#include <iomanip>

using Heads=std::array<std::vector<char>,6>;
volatile std::sig_atomic_t keep_running=1;
void stop_test(int){keep_running=0;}
uint64_t hash_bytes(const std::vector<char>& x){uint64_t h=1469598103934665603ULL;for(unsigned char c:x){h^=c;h*=1099511628211ULL;}return h;}
void save_bytes(const std::string& p,const std::vector<char>& x){std::ofstream f(p,std::ios::binary);f.write(x.data(),x.size());if(!f)throw std::runtime_error("save failed");}

int main(int argc,char**argv)try{
    if(argc!=7)throw std::runtime_error("Usage: config input.bin baseline|convert|local|udp count output_dir destination");
    auto cfg=YAML::LoadFile(argv[1]);std::string mode=argv[3],out=argv[5];int count=std::stoi(argv[4]);
    if(count<1||count>10000||(mode!="baseline"&&mode!="convert"&&mode!="local"&&mode!="udp"))throw std::runtime_error("bad parameters");
    std::filesystem::create_directories(out);std::vector<char> bytes(416*416*3);
    std::ifstream in(argv[2],std::ios::binary);in.read(bytes.data(),bytes.size());if(!in||in.peek()!=EOF)throw std::runtime_error("invalid input length");
    std::signal(SIGINT,stop_test);std::signal(SIGTERM,stop_test);spdlog::set_level(spdlog::level::warn);
    auto device=icraft::xrt::Device::Open(cfg["sys"]["device"].as<std::string>());auto fpai=device.cast<fpai::FPAIDevice>();
    {
        BufferManager buffers(1);auto net=cfg["pipeline"]["icore"];
        Yolov8PLinActor actor(fpai,buffers,net["json"].as<std::string>(),net["raw"].as<std::string>());
        auto session=actor.sessions()[0];auto forward=session.getForwards();auto op=std::get<0>(forward[0]);
        auto info=session->backends[0].cast<fpai::FPAIBackend>()->forward_info;auto vid=op->inputs[0]->v_id;
        auto chunk=info->memchunk_map.at(vid)->memChunk;auto value=info->value_map.at(vid);
        auto input=icraft::xrt::Tensor(value->value);input.setData(chunk,value->phy_addr-chunk->begin.addr());
        input.write(0,bytes.data(),bytes.size());
        std::cout<<"INPUT addr="<<std::hex<<value->phy_addr<<" hash="<<hash_bytes(bytes)<<std::dec<<std::endl;
        bool read_only=std::getenv("FMQL_ISOLATION_READONLY")!=nullptr;
        bool direct_read=std::getenv("FMQL_ISOLATION_DIRECT")!=nullptr;
        bool described=false;
        std::vector<icraft::xrt::Tensor> frozen_outputs;
        std::cout<<"READ_ONLY="<<read_only<<std::endl;
        auto infer=[&](){Heads h;if(!read_only||frozen_outputs.empty())frozen_outputs=session.forward({input});auto& outputs=frozen_outputs;if(outputs.size()!=6)throw std::runtime_error("head count");
            for(int j=0;j<6;++j){if(!outputs[j].waitForReady(std::chrono::milliseconds(10000)))throw std::runtime_error("NPU sync timeout");
                int side=52>>(j/2),channels=j%2?2:64;
                if(!described)std::cout<<"OUTPUT head="<<j<<" on_host="<<outputs[j].isOn(icraft::xrt::HostDevice::MemRegion())<<" region="<<outputs[j].memRegion()->typeKey()<<" addr="<<std::hex<<outputs[j].data().addr()<<std::dec<<" dtype_bytes="<<outputs[j].dtype().bytes()<<std::endl;
                if(direct_read){h[j].resize(outputs[j].dtype().bytes());outputs[j].read(h[j].data(),0,h[j].size());}
                else {auto host=outputs[j].to(icraft::xrt::HostDevice::MemRegion());h[j].assign(host.data().cptr(),host.data().cptr()+side*side*channels*4);}}
            described=true;
            if(!read_only)fpai.reset(1);return h;};
        for(int i=0;i<5;++i)infer();Heads reference=infer();
        for(int j=0;j<6;++j)save_bytes(out+"/reference_"+std::to_string(j)+".bin",reference[j]);
        std::atomic<bool> done{false};std::atomic<uint64_t> producer_frames{0};std::exception_ptr producer_error;
        std::thread worker;
        if(mode!="baseline")worker=std::thread([&]{try{
            std::vector<uint16_t> image(1920*1080);const uint16_t bars[]={0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0};
            for(int y=0;y<1080;++y)for(int x=0;x<1920;++x)image[y*1920+x]=bars[x*8/1920];
            std::vector<uint8_t> nv12(1920*1080*3/2);std::unique_ptr<fmql_video::EthernetVideoSink> sink;
            if(mode!="convert"){fmql_video::VideoOptions opt;opt.url=argv[6];opt.log=out+"/encoder.log";sink=std::make_unique<fmql_video::EthernetVideoSink>(opt);}
            auto start=std::chrono::steady_clock::now();uint64_t n=0;
            while(!done&&keep_running){
                for(int y=950;y<990;++y)for(int x=0;x<1920;++x)image[y*1920+x]=(x/32==n%60)?0xffff:0;
                if(sink)sink->submit(reinterpret_cast<const uint8_t*>(image.data()),image.size()*2);
                else fmql_video::rgb565_nv12(reinterpret_cast<const uint8_t*>(image.data()),1920*2,nv12.data(),1920,1080);
                producer_frames=++n;std::this_thread::sleep_until(start+std::chrono::microseconds(n*1000000/30));
            }if(sink)sink->finish();
        }catch(...){producer_error=std::current_exception();done=true;}});
        size_t mismatched_frames=0,mismatched_bytes=0,input_changes=0;int tested=0;auto start=std::chrono::steady_clock::now();
        try{
            for(int i=0;i<count&&keep_running&&!done;++i){auto actual=infer();size_t diff=0;
                for(int j=0;j<6;++j){size_t first=0,n=0;for(size_t k=0;k<actual[j].size();++k)if(actual[j][k]!=reference[j][k]){if(!n)first=k;++n;}
                    if(n&&mismatched_frames<3){std::cout<<"DIFF iteration="<<i<<" head="<<j<<" bytes="<<n<<" first="<<first<<std::endl;
                        save_bytes(out+"/actual_"+std::to_string(i)+"_"+std::to_string(j)+".bin",actual[j]);}diff+=n;}
                if(diff)++mismatched_frames;mismatched_bytes+=diff;++tested;
                if(i%100==0){auto host=input.to(icraft::xrt::HostDevice::MemRegion());if(std::memcmp(host.data().cptr(),bytes.data(),bytes.size()))++input_changes;}
            }
        }catch(...){done=true;if(worker.joinable())worker.join();throw;}
        done=true;if(worker.joinable())worker.join();if(producer_error)std::rethrow_exception(producer_error);
        auto host=input.to(icraft::xrt::HostDevice::MemRegion());if(std::memcmp(host.data().cptr(),bytes.data(),bytes.size()))++input_changes;
        size_t post_diff=0;for(int repeat=0;repeat<10;++repeat){auto h=infer();for(int j=0;j<6;++j)for(size_t k=0;k<h[j].size();++k)post_diff+=h[j][k]!=reference[j][k];}
        double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
        std::cout<<"ISOLATION_RESULT mode="<<mode<<" tested="<<tested<<" mismatched_frames="<<mismatched_frames<<" mismatched_bytes="<<mismatched_bytes
                 <<" input_changes="<<input_changes<<" post_stop_diff_bytes="<<post_diff<<" producer_frames="<<producer_frames<<" elapsed_s="<<seconds<<" read_only="<<read_only<<std::endl;
        if(read_only)fpai.reset(1);
    }
    icraft::xrt::Device::Close(device);return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<std::endl;return 2;}
