#pragma once
#include "roi_gate_reference.hpp"
#include "yolov8_post.hpp"
#include <cstdint>
#include <vector>

struct RoiGateDecision {
    uint64_t frame=0,event=0;
    Detection detection{};
    int consecutive_hits=0;
    bool confirmed=false,request_eligible=false;
    Mxfp8RoiGateResult gate{};
};
class RoiEventGate {
    struct Track {
        uint64_t id,last_seen=0;Detection detection{};
        int hits=0;bool confirmed=false,requested=false;
    };
    std::vector<Track> tracks_;
    uint64_t next_id_=1,last_frame_=0;
    int confirm_frames_,lost_frames_;size_t max_tracks_;float association_iou_;
    static float overlap(const Box& a,const Box& b){
        float w=std::max(0.f,std::min(a.x+a.width,b.x+b.width)-std::max(a.x,b.x));
        float h=std::max(0.f,std::min(a.y+a.height,b.y+b.height)-std::max(a.y,b.y));
        float area=w*h;return area/(a.area()+b.area()-area+1e-12f);
    }
public:
    RoiEventGate(int confirmation=5,int loss=10,size_t capacity=16,float association=.3f)
        :confirm_frames_(confirmation),lost_frames_(loss),max_tracks_(capacity),association_iou_(association){
        if(confirmation<1||loss<1||capacity<1||capacity>64||association<0||association>1)
            throw std::invalid_argument("Invalid ROI event settings");
    }
    void mark_requested(uint64_t event){for(auto &t:tracks_)if(t.id==event)t.requested=true;}
    std::vector<RoiGateDecision> process(const std::vector<Detection>& detections,int width,int height,uint64_t frame){
        if(frame<=last_frame_||width<=0||height<=0)throw std::invalid_argument("Invalid frame sequence/size");
        last_frame_=frame;
        tracks_.erase(std::remove_if(tracks_.begin(),tracks_.end(),[&](auto &t){return frame-t.last_seen>uint64_t(lost_frames_);}),tracks_.end());
        std::vector<bool> used(tracks_.size(),false);
        std::vector<RoiGateDecision> decisions;
        for(size_t index=0;index<std::min(detections.size(),max_tracks_);++index){
            const auto &d=detections[index];
            if(!std::isfinite(d.score)||!std::isfinite(d.fire_probability)||!std::isfinite(d.smoke_probability)||
               d.score<0||d.score>1||d.fire_probability<0||d.fire_probability>1||d.smoke_probability<0||d.smoke_probability>1)
                throw std::runtime_error("Invalid detector probabilities for ROI features");
            int best=-1;float best_iou=association_iou_;
            for(size_t i=0;i<tracks_.size();++i){
                if(used[i]||tracks_[i].detection.category!=d.category)continue;
                float iou=overlap(tracks_[i].detection.box,d.box);
                if(iou>=best_iou){best=int(i);best_iou=iou;}
            }
            if(best<0){
                if(tracks_.size()>=max_tracks_)continue;
                tracks_.push_back({next_id_++,0,d,0,false,false});
                used.push_back(false);best=int(tracks_.size()-1);
            }
            used[best]=true;auto &track=tracks_[best];
            track.hits=track.last_seen+1==frame?track.hits+1:1;
            track.last_seen=frame;track.detection=d;
            track.confirmed=track.confirmed||track.hits>=confirm_frames_;
            RoiGateDecision decision;
            decision.frame=frame;decision.event=track.id;decision.detection=d;
            decision.consecutive_hits=track.hits;decision.confirmed=track.confirmed;
            // No depth or control sensors are attached to this example.
            // Unavailable depth/control features are explicitly zero/fresh=false.
            mxfp8_roi_features_from_detection(&decision.gate,width,height,1,
                d.fire_probability,d.smoke_probability,d.score,d.box.x,d.box.y,
                d.box.x+d.box.width,d.box.y+d.box.height,track.confirmed,track.confirmed,
                0,0,0,0,0);
            roi_gate_software(decision.gate.feature,decision.gate);
            decision.request_eligible=decision.gate.need_qwen&&!track.requested;
            decisions.push_back(decision);
        }
        tracks_.erase(std::remove_if(tracks_.begin(),tracks_.end(),[&](auto &t){return frame-t.last_seen>=uint64_t(lost_frames_);}),tracks_.end());
        if(decisions.empty()){
            RoiGateDecision empty;empty.frame=frame;
            mxfp8_roi_features_from_detection(&empty.gate,width,height,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
            roi_gate_software(empty.gate.feature,empty.gate);decisions.push_back(empty);
        }
        return decisions;
    }
};
