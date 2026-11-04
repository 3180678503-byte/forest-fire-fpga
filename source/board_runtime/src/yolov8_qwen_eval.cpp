// Offline comparison tool derived from the earlier evaluator.
// RGB letterbox -> UINT8 RGB or SINT8 BGR model -> NPU -> PS DFL/NMS.
// This intentionally separate tool does NOT exercise SDI or ImageMake and
// does NOT alter the live yolov8_plin_hdmi input dataflow.
#include <icraft-xrt/core/session.h>
#include "icraft_utils.hpp"
#include "pipeline/io/input/sdicamera.hpp"
#include "pipeline/io/output/hdmi_display.hpp"
#include <opencv2/opencv.hpp>
#include <yaml-cpp/yaml.h>
#include <filesystem>
#include <fstream>
#include <csignal>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <cctype>
#include "yolov8_decode.hpp"
#include "roi_outbox.hpp"
#include "dfl_fused_cpu.hpp"
#include <iomanip>

using namespace icraft::xrt;
namespace fs=std::filesystem;
volatile std::sig_atomic_t running=1;
void stop_handler(int){running=0;}
struct Geometry {float ratio;int pad_x,pad_y,width,height;};
struct EvalDetection {int cls;float score;cv::Rect2f box;float fire,smoke;};
uint64_t sample_hash(const void* data,size_t bytes){
    auto p=static_cast<const unsigned char*>(data);uint64_t h=1469598103934665603ULL;
    for(size_t i=0;i<bytes;i+=128){h^=p[i];h*=1099511628211ULL;}
    return h;
}
template<class Shape> bool shape_is(const Shape& shape,std::initializer_list<int64_t> expected){
    return shape.size()==expected.size()&&std::equal(shape.begin(),shape.end(),expected.begin());
}

cv::Mat letterbox(const cv::Mat& bgr, Geometry& g) {
    if(bgr.empty() || bgr.type()!=CV_8UC3) throw std::runtime_error("Expected BGR uint8 image");
    g.width=bgr.cols;g.height=bgr.rows;g.ratio=std::min(416.f/g.width,416.f/g.height);
    // nearbyint uses round-to-even, matching Python round for half-way values.
    int w=std::max(1,int(std::nearbyint(double(g.width)*g.ratio)));
    int h=std::max(1,int(std::nearbyint(double(g.height)*g.ratio)));
    g.pad_x=(416-w)/2;g.pad_y=(416-h)/2;
    cv::Mat rgb,resized,canvas(416,416,CV_8UC3,cv::Scalar(114,114,114)),result;
    cv::cvtColor(bgr,rgb,cv::COLOR_BGR2RGB);
    cv::resize(rgb,resized,cv::Size(w,h),0,0,cv::INTER_LINEAR);
    resized.copyTo(canvas(cv::Rect(g.pad_x,g.pad_y,w,h)));
    return canvas;
}

std::vector<EvalDetection> decode(const float* output,Geometry g,float conf,float iou) {
    const int N=3549;
    std::vector<EvalDetection> result;
    for(int cls=0;cls<2;++cls){
        std::vector<cv::Rect2d> boxes;std::vector<float> scores;std::vector<int> indices;
        for(int i=0;i<N;++i){
            float s0=output[4*N+i],s1=output[5*N+i];
            if(!std::isfinite(s0)||!std::isfinite(s1)||s0<0||s0>1.001f||s1<0||s1>1.001f)
                throw std::runtime_error("Invalid decoded class scores");
            int winner=s1>s0?1:0;float score=std::max(s0,s1);
            if(winner!=cls||score<conf) continue;
            float cx=output[i],cy=output[N+i],w=output[2*N+i],h=output[3*N+i];
            if(!std::isfinite(cx)||!std::isfinite(cy)||!std::isfinite(w)||!std::isfinite(h)||w<0||h<0)
                throw std::runtime_error("Invalid decoded box");
            boxes.emplace_back(cx-w/2,cy-h/2,w,h);scores.push_back(score);indices.push_back(i);
        }
        std::vector<int> order,keep;
        for(size_t i=0;i<scores.size();++i)if(scores[i]>conf)order.push_back(int(i));
        std::stable_sort(order.begin(),order.end(),[&](int a,int b){return scores[a]>scores[b];});
        for(int i:order){
            bool suppressed=false;
            for(int j:keep){
                double intersection=(boxes[i]&boxes[j]).area();
                double overlap=intersection/(boxes[i].area()+boxes[j].area()-intersection+1e-12);
                if(overlap>iou){suppressed=true;break;}
            }
            if(!suppressed)keep.push_back(i);
        }
        for(int i:keep){
            auto b=boxes[i];float x1=std::clamp(float((b.x-g.pad_x)/g.ratio),0.f,float(g.width));
            float y1=std::clamp(float((b.y-g.pad_y)/g.ratio),0.f,float(g.height));
            float x2=std::clamp(float((b.x+b.width-g.pad_x)/g.ratio),0.f,float(g.width));
            float y2=std::clamp(float((b.y+b.height-g.pad_y)/g.ratio),0.f,float(g.height));
            if(x2>x1&&y2>y1) result.push_back({cls,scores[i],cv::Rect2f(x1,y1,x2-x1,y2-y1),output[4*N+indices[i]],output[5*N+indices[i]]});
        }
    }
    std::sort(result.begin(),result.end(),[](auto a,auto b){return a.score>b.score;});
    return result;
}

void write_binary(const std::string& name,const void* data,size_t bytes){
    auto parent=fs::path(name).parent_path();if(!parent.empty())fs::create_directories(parent);
    std::ofstream f(name,std::ios::binary);f.write(static_cast<const char*>(data),bytes);
    if(!f)throw std::runtime_error("Cannot write "+name);
}

int main(int argc,char** argv)try{
    if(argc<2){std::cerr<<"Usage: yolov8_plin_eval config.yaml --dataset images --output-dir results [--frames N]\n";return 1;}
    std::string image_file,tensor_file,dump,replay_file,dataset_dir,output_dir,roi_directory;int frames=0,drain_ms=2000,review_class=-1;uint64_t roi_frame=0;
    for(int i=2;i<argc;++i){
        std::string flag=argv[i];if(i+1>=argc)throw std::runtime_error("Missing value for "+flag);
        if(flag=="--roi-output")roi_directory=argv[++i];
        else if(flag=="--review-drain-ms")drain_ms=std::stoi(argv[++i]);
        else if(flag=="--review-class"){std::string c=argv[++i];review_class=c=="fire"?0:c=="smoke"?1:-1;}
        else if(flag=="--image")image_file=argv[++i];else if(flag=="--tensor")tensor_file=argv[++i];
        else if(flag=="--dump")dump=argv[++i];else if(flag=="--frames")frames=std::stoi(argv[++i]);
        else if(flag=="--replay")replay_file=argv[++i];
        else if(flag=="--dataset")dataset_dir=argv[++i];
        else if(flag=="--output-dir")output_dir=argv[++i];
        else throw std::runtime_error("Unknown option "+flag);
    }
    if(!image_file.empty()&&!tensor_file.empty())throw std::runtime_error("Choose image or tensor");
    if(!replay_file.empty()&&image_file.empty())throw std::runtime_error("Replay requires --image");
    if(!dataset_dir.empty()&&(!image_file.empty()||!tensor_file.empty()||output_dir.empty()))throw std::runtime_error("Dataset mode requires --output-dir and no single-image option");
    std::unique_ptr<RoiOutbox> outbox;
    YAML::Node cfg=YAML::LoadFile(argv[1]);auto model=cfg["model"];auto cam_cfg=cfg["camera"];
    size_t review_budget=cfg["qwen"]&&cfg["qwen"]["max_jobs"]?cfg["qwen"]["max_jobs"].as<size_t>():8;
    if(!roi_directory.empty())outbox=std::make_unique<RoiOutbox>(roi_directory,1,review_budget,0);
    auto network=loadNetwork(model["json"].as<std::string>(),model["raw"].as<std::string>());
    if(network.inputs().size()!=1)throw std::runtime_error("Expected one model input");
    auto input_type=network.inputs()[0].tensorType();
    if(!shape_is(input_type->shape,{1,416,416,3}) || input_type->element_dtype.getStorageType().bits()!=8)
        throw std::runtime_error("Expected NHWC 8-bit [1,416,416,3] model input");
    bool signed_bgr=!input_type->element_dtype.getStorageType().cast<icraft::xir::IntegerType>().isUInt8();
    auto device=Device::Open(cfg["device"].as<std::string>());auto fpai=device.cast<fpai::FPAIDevice>();
    const size_t input_bytes=416*416*3;
    auto session=initSession("zg330",network,fpai,-1,true,false,false);
    Tensor input(input_type);input.mallocOn(HostDevice::MemRegion());
    session.apply();
    const float conf=model["conf"].as<float>(),iou=model["iou"].as<float>();
    std::string current_image_name;
    fs::create_directories(fs::path(output_dir)/"dense");fs::create_directories(fs::path(output_dir)/"fused");fs::create_directories(fs::path(output_dir)/"crops");
    std::ofstream compare_index(fs::path(output_dir)/"decoder_comparison.csv");
    compare_index<<"image,detections,dense_dfl_nms_ms,fused_dfl_nms_ms,detection_max_abs_error,selected_max_abs_error,numeric_fallback\n";
    int last_detection_count=0;double last_inference_ms=0;
    double input_write_ms=0,npu_ms=0,post_ms=0;
    auto milliseconds=[](auto begin,auto end){return std::chrono::duration<double,std::milli>(end-begin).count();};
    auto infer=[&](const cv::Mat& x,Geometry g,cv::Mat& frame,const std::string& prefix){
        auto input_begin=std::chrono::steady_clock::now();
        input.write(0,reinterpret_cast<char*>(x.data),input_bytes);
        auto ts=std::chrono::steady_clock::now();
        input_write_ms=milliseconds(input_begin,ts);
        auto outputs=session.forward({input});
        if(outputs.size()!=6)throw std::runtime_error("Expected six raw YOLOv8 head tensors");
        std::vector<Tensor> host_heads;std::array<const float*,6> head_data;
        for(int i=0;i<6;++i){
            if(!outputs[i].waitForReady(std::chrono::milliseconds(10000)))throw std::runtime_error("Output tensor readiness timeout");
            auto type=outputs[i].dtype();
            int side=52>>(i/2),channels=i%2?2:64;
            if(!shape_is(type->shape,{1,side,side,channels})||type->element_dtype.getStorageType().bits()!=32)
                throw std::runtime_error("Expected six NHWC FP32 heads, ordered box/class for strides 8,16,32");
            host_heads.push_back(outputs[i].to(HostDevice::MemRegion()));
            head_data[i]=reinterpret_cast<const float*>(host_heads.back().data().cptr());
        }
        // Match the vendor NPU actor: finish output synchronization, then clear
        // the ZG330 execution counters/handshake before processing another frame.
        // Without reset(1), readiness checks can match the preceding inference.
        fpai.reset(1);
        auto npu_end=std::chrono::steady_clock::now();
        npu_ms=milliseconds(ts,npu_end);
        auto dense_begin=std::chrono::steady_clock::now();
        auto dense=decode_yolov8_heads(head_data);
        auto dense_det=decode(dense.data(),g,conf,iou);
        auto dense_end=std::chrono::steady_clock::now();
        auto fused_begin=dense_end;
        auto fused=dfl_fused_cpu(head_data,conf,++roi_frame);
        auto decoded=std::move(fused.values);auto values=decoded.data();
        auto det=decode(values,g,conf,iou);
        auto fused_end=std::chrono::steady_clock::now();
        float selected_error=dfl_compare_selected(dense,decoded,conf);
        if(det.size()!=dense_det.size())throw std::runtime_error("Dense/fused count mismatch");
        double detection_max_abs_error=0;
        for(size_t n=0;n<det.size();++n){
            auto a=det[n],b=dense_det[n];
            if(a.cls!=b.cls)throw std::runtime_error("Dense/fused class mismatch");
            for(double delta:{double(a.score-b.score),double(a.box.x-b.box.x),double(a.box.y-b.box.y),double(a.box.width-b.box.width),double(a.box.height-b.box.height)})
                detection_max_abs_error=std::max(detection_max_abs_error,std::abs(delta));
        }
        if(detection_max_abs_error>.001)throw std::runtime_error("Dense/fused detection mismatch");
        const auto stem=fs::path(current_image_name).stem().string();
        auto root=fs::path(output_dir);
        write_binary((root/"dense"/(stem+".output_1x6x3549_fp32.bin")).string(),dense.data(),dense.size()*4);
        std::ofstream dense_csv(root/"dense"/(stem+".detections.csv"));dense_csv<<std::setprecision(9)<<"class_id,score,left,top,width,height\n";
        std::ofstream fused_csv(root/"fused"/(stem+".detections.csv"));fused_csv<<std::setprecision(9)<<"class_id,score,left,top,width,height,eligible,crop_file\n";
        for(auto d:dense_det)dense_csv<<d.cls<<","<<d.score<<","<<d.box.x<<","<<d.box.y<<","<<d.box.width<<","<<d.box.height<<"\n";
        std::vector<Detection> proposals;for(auto d:det)proposals.push_back({d.cls,d.score,{d.box.x,d.box.y,d.box.width,d.box.height},d.fire,d.smoke});
        RoiEventGate gate(5,10,16,.30f);auto decisions=gate.process(proposals,g.width,g.height,1);
        for(size_t n=0;n<det.size();++n){
            auto d=det[n];bool eligible=false;
            for(const auto& decision:decisions)if(decision.request_eligible&&decision.detection.category==d.cls&&decision.detection.box.x==d.box.x&&decision.detection.box.y==d.box.y)eligible=true;
            std::string crop_file;
            if(eligible){
                float px=std::max(8.f,d.box.width*.2f),py=std::max(8.f,d.box.height*.2f);
                int x0=std::max(0,int(std::floor(d.box.x-px))),y0=std::max(0,int(std::floor(d.box.y-py)));
                int x1=std::min(g.width,int(std::ceil(d.box.x+d.box.width+px))),y1=std::min(g.height,int(std::ceil(d.box.y+d.box.height+py)));
                cv::Mat crop=frame(cv::Rect(x0,y0,x1-x0,y1-y0)).clone();
                if(std::max(crop.cols,crop.rows)>640){double ratio=640./std::max(crop.cols,crop.rows);cv::resize(crop,crop,{},ratio,ratio,cv::INTER_AREA);}
                crop_file=stem+"_"+std::to_string(n)+".jpg";
                if(!cv::imwrite((root/"crops"/crop_file).string(),crop,{cv::IMWRITE_JPEG_QUALITY,85}))throw std::runtime_error("Crop export failed");
            }
            fused_csv<<d.cls<<","<<d.score<<","<<d.box.x<<","<<d.box.y<<","<<d.box.width<<","<<d.box.height<<","<<eligible<<","<<crop_file<<"\n";
        }
        compare_index<<current_image_name<<","<<det.size()<<","<<milliseconds(dense_begin,dense_end)<<","<<milliseconds(fused_begin,fused_end)<<","<<detection_max_abs_error<<","<<selected_error<<","<<fused.fallback<<"\n";compare_index.flush();
        post_ms=milliseconds(npu_end,std::chrono::steady_clock::now());
        last_detection_count=int(det.size());
        double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-ts).count();
        last_inference_ms=ms;
        std::cout<<"inference+decode_ms="<<ms<<", detections="<<det.size()
                 <<", max_fire_score="<<*std::max_element(values+4*3549,values+5*3549)
                 <<", max_smoke_score="<<*std::max_element(values+5*3549,values+6*3549)<<std::endl;
        std::cout<<"HASH input="<<std::hex<<sample_hash(x.data,input_bytes)
                 <<", output="<<sample_hash(values,6*3549*sizeof(float))<<std::dec<<std::endl;
        if(outbox){
            ++roi_frame;std::vector<Detection> proposals;
            for(const auto& item:det)if(review_class<0||review_class==item.cls)proposals.push_back({item.cls,item.score,{item.box.x,item.box.y,item.box.width,item.box.height},item.fire,item.smoke});
            RoiEventGate image_gate(5,10,16,.30f);
            auto decisions=image_gate.process(proposals,g.width,g.height,1);
            for(auto d:decisions){d.event+=roi_frame*1000;d.frame=roi_frame;if(outbox->submit(d,frame))break;}
            auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(drain_ms);
            while(outbox->pending()&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
        for(auto d:det){
            std::cout<<(d.cls==0?"fire":"smoke")<<","<<d.score<<","<<d.box.x<<","<<d.box.y<<","<<d.box.width<<","<<d.box.height<<"\n";
            if(!frame.empty()){
                cv::rectangle(frame,d.box,cv::Scalar(0,165,255),2);
                cv::putText(frame,(d.cls==0?"fire ":"smoke ")+std::to_string(d.score),d.box.tl(),cv::FONT_HERSHEY_SIMPLEX,.6,cv::Scalar(0,165,255),2);
            }
        }
        if(!prefix.empty()){
            write_binary(prefix+".input_nhwc_uint8.bin",x.data,input_bytes);
            write_binary(prefix+".output_1x6x3549_fp32.bin",values,6*3549*sizeof(float));
            std::ofstream f(prefix+".detections.csv");f<<"class_id,score,left,top,width,height\n";
            for(auto d:det)f<<d.cls<<","<<d.score<<","<<d.box.x<<","<<d.box.y<<","<<d.box.width<<","<<d.box.height<<"\n";
            if(!frame.empty())cv::imwrite(prefix+".annotated.png",frame);
        }
        return decoded;
    };
    if(!dataset_dir.empty()){
        fs::create_directories(output_dir);
        std::vector<fs::path> images;
        for(const auto& item:fs::directory_iterator(dataset_dir)){
            auto ext=item.path().extension().string();
            std::transform(ext.begin(),ext.end(),ext.begin(),[](unsigned char c){return std::tolower(c);});
            if(item.is_regular_file()&&(ext==".jpg"||ext==".jpeg"||ext==".png"||ext==".bmp"))images.push_back(item.path());
        }
        std::sort(images.begin(),images.end());
        if(images.empty())throw std::runtime_error("Empty image dataset");
        std::ofstream index(fs::path(output_dir)/"index.csv");
        index<<"image,width,height,ratio,pad_x,pad_y,inference_decode_ms,pipeline_ms,detections,read_preprocess_ms,input_write_ms,npu_sync_download_reset_ms,dfl_nms_ms\n";
        std::signal(SIGINT,stop_handler);std::signal(SIGTERM,stop_handler);
        int processed=0;
        for(const auto& path:images){
            if(!running||(frames>0&&processed>=frames))break;
            auto begin=std::chrono::steady_clock::now();
            cv::Mat frame=cv::imread(path.string(),cv::IMREAD_COLOR);
            if(frame.empty()||frame.type()!=CV_8UC3)
                throw std::runtime_error("Invalid imread: "+path.string()+", rows="+std::to_string(frame.rows)+
                    ", cols="+std::to_string(frame.cols)+", type="+std::to_string(frame.type()));
            Geometry g;auto x=letterbox(frame,g);
            if(signed_bgr){
                cv::Mat bgr_input,physical;
                cv::cvtColor(x,bgr_input,cv::COLOR_RGB2BGR);
                bgr_input.convertTo(physical,CV_8SC3,1.0,-128.0);x=physical;
            }
            double preprocess_ms=milliseconds(begin,std::chrono::steady_clock::now());
            std::cout<<"BATCH image="<<path.filename().string()<<std::endl;
            current_image_name=path.filename().string();
            auto decoded=infer(x,g,frame,"");
            double pipeline_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
            auto prefix=(fs::path(output_dir)/path.stem()).string();
            write_binary(prefix+".output_1x6x3549_fp32.bin",decoded.data(),decoded.size()*sizeof(float));
            index<<path.filename().string()<<","<<g.width<<","<<g.height<<","<<g.ratio<<","<<g.pad_x<<","<<g.pad_y<<","<<last_inference_ms<<","<<pipeline_ms<<","<<last_detection_count<<","<<preprocess_ms<<","<<input_write_ms<<","<<npu_ms<<","<<post_ms<<"\n";
            index.flush();
            if(processed<12){
                cv::imwrite(prefix+".annotated.png",frame);
                write_binary(prefix+(signed_bgr?".input_nhwc_sint8_bgr.bin":".input_nhwc_uint8.bin"),x.data,416*416*3);
            }
            ++processed;
        }
        std::cout<<"Batch summary: processed="<<processed<<", available="<<images.size()<<std::endl;
        Device::Close(device);return running?0:130;
    }
    throw std::runtime_error("Use --dataset and --output-dir; this tool does not access the camera");
}catch(const std::exception& e){std::cerr<<e.what()<<std::endl;return 2;}
