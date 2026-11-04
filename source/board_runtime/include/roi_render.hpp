#pragma once
#include "yolov8_post.hpp"
#include <opencv2/opencv.hpp>
namespace optimized_render {
inline void overlay(cv::Mat& rgb565,const std::vector<Detection>& detections,const std::array<const char*,2>& labels,uint64_t count,double fps,bool roi){
    const cv::Rect image(0,0,rgb565.cols,rgb565.rows);
    cv::Mat full;
    if(!roi)cv::cvtColor(rgb565,full,cv::COLOR_BGR5652BGR);
    auto draw=[&](cv::Rect bounds,auto operation){
        if(!roi){operation(full,cv::Point());return;}
        bounds &= image;if(bounds.empty())return;
        cv::Mat patch;cv::cvtColor(rgb565(bounds),patch,cv::COLOR_BGR5652BGR);
        operation(patch,bounds.tl());cv::cvtColor(patch,rgb565(bounds),cv::COLOR_BGR2BGR565);
    };
    auto text=[&](const std::string& value,cv::Point anchor,double size,cv::Scalar color){
        int baseline=0;auto extent=cv::getTextSize(value,cv::FONT_HERSHEY_SIMPLEX,size,1,&baseline);
        draw(cv::Rect(anchor.x-4,anchor.y-extent.height-5,extent.width+8,extent.height+baseline+10),
            [&](cv::Mat& bgr,cv::Point offset){cv::putText(bgr,value,anchor-offset,cv::FONT_HERSHEY_SIMPLEX,size,color,1);});
    };
    for(const auto& d:detections){
        cv::Scalar color=d.category==0?cv::Scalar(0,100,255):cv::Scalar(0,220,255);
        cv::Rect rect=cv::Rect2f(d.box.x,d.box.y,d.box.width,d.box.height);
        draw(cv::Rect(rect.x-4,rect.y-4,rect.width+8,rect.height+8),
            [&](cv::Mat& bgr,cv::Point offset){auto shifted=rect;shifted.x-=offset.x;shifted.y-=offset.y;cv::rectangle(bgr,shifted,color,2);});
        text(fmt::format("{} {:.2f}",labels[d.category],d.score),{int(d.box.x),std::max(18,int(d.box.y))},.6,color);
    }
    text(fmt::format("PLIN YOLOv8  FRAME {}  FPS {:.1f}",count,fps),{15,35},.8,{0,255,0});
    if(!roi)cv::cvtColor(full,rgb565,cv::COLOR_BGR2BGR565);
}
}
