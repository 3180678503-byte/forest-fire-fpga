#include "roi_outbox.hpp"
#include <iostream>

int main(int argc,char**argv)try{
    if(argc!=2)throw std::runtime_error("Expected fresh output directory");
    cv::Mat original(1080,1920,CV_8UC3);cv::RNG rng(20261019);rng.fill(original,cv::RNG::UNIFORM,0,256);
    cv::Mat rgb565;cv::cvtColor(original,rgb565,cv::COLOR_BGR2BGR565);
    std::vector<cv::Rect> cases={{100,200,60,40},{1,2,40,45},{0,0,1920,1080},{200,200,600,600}};
    for(size_t n=0;n<cases.size();++n){
        auto b=cases[n];auto root=std::filesystem::path(argv[1])/std::to_string(n);
        RoiGateDecision d;d.frame=1;d.event=n+1;d.request_eligible=true;
        d.detection={0,.6f,{float(b.x),float(b.y),float(b.width),float(b.height)},.6f,.2f};
        float px=std::max(8.f,b.width*.2f),py=std::max(8.f,b.height*.2f);
        int x=std::max(0,int(std::floor(b.x-px))),y=std::max(0,int(std::floor(b.y-py)));
        int right=std::min(1920,int(std::ceil(b.x+b.width+px))),bottom=std::min(1080,int(std::ceil(b.y+b.height+py)));
        cv::Mat reference;cv::cvtColor(rgb565(cv::Rect(x,y,right-x,bottom-y)),reference,cv::COLOR_BGR5652BGR);
        if(std::max(reference.cols,reference.rows)>640){double scale=640./std::max(reference.cols,reference.rows);cv::resize(reference,reference,{},scale,scale,cv::INTER_AREA);}
        std::vector<unsigned char> expected;cv::imencode(".jpg",reference,expected,{cv::IMWRITE_JPEG_QUALITY,85});
        {RoiOutbox out(root.string());if(!out.submit(d,rgb565))throw std::runtime_error("ROI submit rejected");
            auto path=root/"requests"/(roi_request_stem(d.event,d.frame)+".json");
            auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
            while(!std::filesystem::exists(path)&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(10));
            if(!std::filesystem::exists(path))throw std::runtime_error("ROI not published");out.finish();}
        auto jpg=root/"requests"/(roi_request_stem(d.event,d.frame)+".jpg");std::ifstream f(jpg,std::ios::binary);
        std::vector<unsigned char> actual((std::istreambuf_iterator<char>(f)),{});
        if(actual.size()>128*1024)throw std::runtime_error("JPEG exceeds ESP limit");
        if(expected.size()<=128*1024&&actual!=expected)throw std::runtime_error("RGB565 crop differs from reference JPEG");
        if(cv::imdecode(actual,cv::IMREAD_COLOR).empty())throw std::runtime_error("JPEG cannot decode");
        auto meta=YAML::LoadFile((root/"requests"/(roi_request_stem(d.event,d.frame)+".json")).string());
        if(meta["source_width"].as<int>()!=1920||meta["source_height"].as<int>()!=1080||meta["crop"][0].as<int>()!=x||meta["crop"][1].as<int>()!=y||meta["crop"][2].as<int>()!=right-x||meta["crop"][3].as<int>()!=bottom-y)
            throw std::runtime_error("ROI metadata geometry mismatch");
    }
    auto complete=[&](RoiOutbox& out,const std::filesystem::path& root,uint64_t event){
        RoiGateDecision d;d.frame=event;d.event=event;d.request_eligible=true;
        d.detection={0,.6f,{100,100,40,40},.6f,.2f};
        if(!out.submit(d,rgb565))throw std::runtime_error("Budget submit unexpectedly rejected");
        auto stem=roi_request_stem(event,event);
        auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
        while(!std::filesystem::exists(root/"requests"/(stem+".json"))&&std::chrono::steady_clock::now()<deadline)
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        if(!std::filesystem::exists(root/"requests"/(stem+".json")))throw std::runtime_error("Budget publish failed");
        std::ofstream f(root/"reviews"/(stem+".json"));
        f<<"{\"event_id\":"<<event<<",\"frame\":"<<event<<",\"backend\":\"mock\",\"status\":\"completed\",\"semantic\":{\"verdict\":\"UNCERTAIN\",\"reason_code\":\"UNKNOWN\",\"evidence\":\"test\",\"confidence\":0}}";f.close();
        while(out.pending()&&std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(10));
        if(out.pending())throw std::runtime_error("Review not consumed");
    };
    auto unlimited=std::filesystem::path(argv[1])/"unlimited";
    {RoiOutbox out(unlimited.string(),1,0,0);for(uint64_t i=1;i<=10;++i)complete(out,unlimited,i);}
    auto limited=std::filesystem::path(argv[1])/"limited";
    {RoiOutbox out(limited.string(),1,1,0);complete(out,limited,1);
        RoiGateDecision d;d.request_eligible=true;if(out.submit(d,rgb565))throw std::runtime_error("Budget exceeded");}
    auto cooled=std::filesystem::path(argv[1])/"cooldown";
    {RoiOutbox out(cooled.string(),1,0,.3);complete(out,cooled,1);
        RoiGateDecision d;d.request_eligible=true;if(out.submit(d,rgb565))throw std::runtime_error("Cooldown ignored");
        std::this_thread::sleep_for(std::chrono::milliseconds(350));complete(out,cooled,2);}
    std::cout<<"{\"crop_cases\":4,\"unchanged_jpeg_when_within_limit\":true,\"jpeg_limit\":131072,\"unlimited_jobs\":10,\"budget_and_cooldown\":true}"<<std::endl;return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<std::endl;return 2;}
