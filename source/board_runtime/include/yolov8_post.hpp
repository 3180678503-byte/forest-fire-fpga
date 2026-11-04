#pragma once
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
#include <stdexcept>
#include "yolov8_decode.hpp"
#ifdef FMQL_PROFILE
#include "plin_profile.hpp"
#endif

struct Box {float x,y,width,height;float area()const{return width*height;}};
struct Detection { int category; float score; Box box; float fire_probability=0,smoke_probability=0; };
struct HardwareGeometry {
    int source_w,source_h,net_w,net_h,stride_x,stride_y,bias_x,bias_y;
    static HardwareGeometry center(int sw,int sh,int nw,int nh) {
        if(sw<nw||sh<nh||nw<=0||nh<=0)throw std::invalid_argument("Invalid hardware resize geometry");
        int sx=sw/nw,sy=sh/nh;
        return {sw,sh,nw,nh,sx,sy,(sw-sx*nw)/2,(sh-sy*nh)/2};
    }
    Box restore(float x1,float y1,float x2,float y2)const {
        float left=std::clamp(x1*stride_x+bias_x,0.f,float(source_w));
        float top=std::clamp(y1*stride_y+bias_y,0.f,float(source_h));
        float right=std::clamp(x2*stride_x+bias_x,0.f,float(source_w));
        float bottom=std::clamp(y2*stride_y+bias_y,0.f,float(source_h));
        return {left,top,std::max(0.f,right-left),std::max(0.f,bottom-top)};
    }
};

inline std::vector<Detection> detect_yolov8(const std::vector<float>& raw,
                                         const HardwareGeometry& geometry,float confidence,float iou
#ifdef FMQL_PROFILE
                                         ,fmql_profile::Frame* profile=nullptr
#endif
                                         ) {
#ifdef FMQL_PROFILE
    auto stage_start=fmql_profile::now_ns();
#endif
    constexpr int cells=3549;
    if(raw.size()!=6*cells)throw std::runtime_error("Unexpected YOLOv8 decoded output shape");
    struct Candidate {int category;float score;Box box;float fire_probability,smoke_probability;};
    std::vector<Candidate> candidates;
    for(int i=0;i<cells;++i){
        float a=raw[4*cells+i],b=raw[5*cells+i];
        if(!std::isfinite(a)||!std::isfinite(b)||a<0||b<0||a>1||b>1)
            throw std::runtime_error("Invalid class scores");
        int category=b>a?1:0;float score=std::max(a,b);
        if(score<=confidence)continue;
        float cx=raw[i],cy=raw[cells+i],w=raw[2*cells+i],h=raw[3*cells+i];
        if(!std::isfinite(cx)||!std::isfinite(cy)||!std::isfinite(w)||!std::isfinite(h)||w<0||h<0)
            throw std::runtime_error("Invalid box values");
        candidates.push_back({category,score,{cx-w/2,cy-h/2,w,h},a,b});
    }
#ifdef FMQL_PROFILE
    if(profile)profile->confidence_filter_ms=fmql_profile::ms(fmql_profile::now_ns(),stage_start);
    stage_start=fmql_profile::now_ns();
#endif
    std::stable_sort(candidates.begin(),candidates.end(),[](const auto& a,const auto& b){return a.score>b.score;});
#ifdef FMQL_PROFILE
    if(profile)profile->sort_ms=fmql_profile::ms(fmql_profile::now_ns(),stage_start);
    stage_start=fmql_profile::now_ns();
#endif
    std::vector<Candidate> selected;
    for(const auto& item:candidates){
        bool suppressed=false;
        for(const auto& previous:selected){
            if(item.category!=previous.category)continue;
            float width=std::max(0.f,std::min(item.box.x+item.box.width,previous.box.x+previous.box.width)-std::max(item.box.x,previous.box.x));
            float height=std::max(0.f,std::min(item.box.y+item.box.height,previous.box.y+previous.box.height)-std::max(item.box.y,previous.box.y));
            float intersection=width*height;
            float overlap=intersection/(item.box.area()+previous.box.area()-intersection+1e-12f);
            if(overlap>iou){suppressed=true;break;}
        }
        if(!suppressed){selected.push_back(item);if(selected.size()==300)break;}
    }
#ifdef FMQL_PROFILE
    if(profile)profile->nms_ms=fmql_profile::ms(fmql_profile::now_ns(),stage_start);
    stage_start=fmql_profile::now_ns();
#endif
    std::vector<Detection> result;
    for(const auto& item:selected){
        auto box=geometry.restore(item.box.x,item.box.y,item.box.x+item.box.width,item.box.y+item.box.height);
        if(box.width>0&&box.height>0)result.push_back({item.category,item.score,box,item.fire_probability,item.smoke_probability});
    }
#ifdef FMQL_PROFILE
    if(profile)profile->box_restore_ms=fmql_profile::ms(fmql_profile::now_ns(),stage_start);
#endif
    return result;
}
