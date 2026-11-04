#include "ethernet_video_sink.hpp"
#include <fstream>
#include <random>

static void converter_test() {
    // Every RGB565 value, random second row, non-vector tail and padded stride.
    for(int w:{2,14,130,1920}) {
        int h=72;size_t stride=size_t(w)*2+16;
        std::vector<uint16_t> source(stride*h/2);
        std::mt19937 rng(5641);
        for(size_t i=0;i<source.size();++i)source[i]=uint16_t(i<65536?i:rng());
        std::vector<uint8_t> a(size_t(w)*h*3/2),b(a.size());
        fmql_video::rgb565_nv12(reinterpret_cast<uint8_t*>(source.data()),stride,a.data(),w,h,false);
        fmql_video::rgb565_nv12(reinterpret_cast<uint8_t*>(source.data()),stride,b.data(),w,h,true);
        if(a!=b)throw std::runtime_error("NEON differs from scalar converter");
    }
    uint16_t black[4]={0,0,0,0};uint8_t yuv[6];
    fmql_video::rgb565_nv12(reinterpret_cast<uint8_t*>(black),4,yuv,2,2);
    if(yuv[0]!=16||yuv[4]!=128||yuv[5]!=128)throw std::runtime_error("Black color conversion failed");
    uint16_t white[4]={65535,65535,65535,65535};
    fmql_video::rgb565_nv12(reinterpret_cast<uint8_t*>(white),4,yuv,2,2);
    if(yuv[0]!=235||yuv[4]!=128||yuv[5]!=128)throw std::runtime_error("White color conversion failed");
    std::cout<<"CONVERTER_PASS neon_equals_scalar=1 padded_stride=1 tail=1 black_white=1\n";
}

int main(int argc,char**argv)try {
    converter_test();
    fmql_video::VideoOptions options;int frames=90;bool pace=false;std::string raw;
    for(int i=1;i<argc;++i) {
        std::string arg=argv[i];
        if(arg=="--selftest-only")return 0;
        if(arg=="--pace"){pace=true;continue;}
        if(i+1>=argc)throw std::invalid_argument("Missing argument");
        if(arg=="--url")options.url=argv[++i];
        else if(arg=="--frames")frames=std::stoi(argv[++i]);
        else if(arg=="--fps")options.fps=std::stoi(argv[++i]);
        else if(arg=="--log")options.log=argv[++i];
        else if(arg=="--ffmpeg")options.ffmpeg=argv[++i];
        else if(arg=="--rgb565")raw=argv[++i];
        else throw std::invalid_argument("Unknown flag");
    }
    if(frames<1||frames>100000)throw std::invalid_argument("Invalid frame count");
    std::vector<uint16_t> image(size_t(options.width)*options.height);
    const uint16_t bars[]={0xffff,0xffe0,0x07ff,0x07e0,0xf81f,0xf800,0x001f,0};
    for(int y=0;y<options.height;++y)for(int x=0;x<options.width;++x)
        image[size_t(y)*options.width+x]=bars[x*8/options.width];
    if(!raw.empty()) {
        std::ifstream in(raw,std::ios::binary);in.read(reinterpret_cast<char*>(image.data()),image.size()*2);
        if(!in||in.peek()!=EOF)throw std::runtime_error("Expected exactly one 1920x1080 RGB565 frame");
    }
    fmql_video::EthernetVideoSink sink(options);auto start=std::chrono::steady_clock::now();
    for(int n=0;n<frames;++n) {
        auto frame=image;
        for(int y=950;y<990;++y)for(int x=0;x<options.width;++x)
            frame[size_t(y)*options.width+x]=(x/32==n%60)?0xffff:0;
        sink.submit(reinterpret_cast<uint8_t*>(frame.data()),frame.size()*2);
        if(pace)std::this_thread::sleep_until(start+std::chrono::microseconds(int64_t(n+1)*1000000/options.fps));
    }
    sink.finish();std::cout<<"VIDEO_PROBE_PASS\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<std::endl;return 2;}
