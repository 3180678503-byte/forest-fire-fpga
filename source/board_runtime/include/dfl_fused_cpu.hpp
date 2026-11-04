#pragma once
#include "yolov8_decode.hpp"
#include "dfl_decode_v1.h"
#include <cstring>
#include <cstdint>

// ARM FP32 reference of the supplied candidate packet ABI. No MMIO/PL calls.
struct DflCpuResult {
    std::vector<float> values;
    std::vector<unsigned char> packet;
    unsigned selected=0;
    bool fallback=false;
};
inline float dfl_sigmoid(float x){
    if(!std::isfinite(x))throw std::runtime_error("Non-finite class logit");
    float e=std::exp(x>=0?-x:x);return x>=0?1.f/(1.f+e):e/(1.f+e);
}
inline DflCpuResult dfl_fused_cpu(const std::array<const float*,6>& heads,float confidence,uint64_t frame_id){
    if(!std::isfinite(confidence)||confidence<0||confidence>1)throw std::runtime_error("Invalid confidence");
    struct Job {int level,cell,index,category;float score;};
    std::vector<Job> jobs;jobs.reserve(64);
    bool guard=false;int offset=0;
    for(int level=0;level<3;++level){
        int side=52>>level,cells=side*side;auto box=heads[2*level];auto cls=heads[2*level+1];
        // STRICT_FINITE in the provided ABI checks every input, even rejected cells.
        for(int i=0;i<cells*64;++i)if(!std::isfinite(box[i]))throw std::runtime_error("Non-finite box logit");
        for(int i=0;i<cells;++i){
            float a=dfl_sigmoid(cls[2*i]),b=dfl_sigmoid(cls[2*i+1]),winner=std::max(a,b);
            if(std::abs(winner-confidence)<=2e-5f)guard=true;
            if(winner>confidence&&cls[2*i]!=cls[2*i+1]&&std::abs(a-b)<=2e-5f)guard=true;
            if(winner>confidence)jobs.push_back({level,i,offset+i,b>a?1:0,winner});
        }
        offset+=cells;
    }
    DflCpuResult result;result.selected=unsigned(jobs.size());result.fallback=guard;
    dfl_v1_result_header header{};
    header.magic=DFL_V1_ID;header.abi=DFL_V1_ABI;header.frame_id=frame_id;
    header.capacity=3549;header.record_bytes=32;header.conf_f32_bits=dfl_v1_float_bits(confidence);
    if(guard){
        header.error_code=DFL_E_NUMERIC_FALLBACK;
        result.packet.resize(64);std::memcpy(result.packet.data(),&header,64);
        result.values=decode_yolov8_heads(heads);return result;
    }
    std::vector<dfl_v1_candidate> records;records.reserve(jobs.size());
    for(const auto& job:jobs){
        int side=52>>job.level,stride=8<<job.level,x=job.cell%side,y=job.cell/side;float d[4];
        for(int axis=0;axis<4;++axis){
            auto logits=heads[2*job.level]+job.cell*64+axis*16;
            float maximum=*std::max_element(logits,logits+16),sum=0,weighted=0;
            for(int bin=0;bin<16;++bin){float p=std::exp(logits[bin]-maximum);sum+=p;weighted+=p*bin;}
            d[axis]=weighted/sum;
        }
        dfl_v1_candidate record{};record.cell_index=job.index;record.class_id=job.category;record.score=job.score;
        record.cx=(x+.5f+(d[2]-d[0])*.5f)*stride;record.cy=(y+.5f+(d[3]-d[1])*.5f)*stride;
        record.width=(d[0]+d[2])*stride;record.height=(d[1]+d[3])*stride;records.push_back(record);
    }
    header.flags=DFL_RESULT_VALID;header.candidate_total=header.candidate_written=records.size();
    header.payload_bytes=records.size()*32;
    result.packet.resize(64+header.payload_bytes);std::memcpy(result.packet.data(),&header,64);
    if(!records.empty())std::memcpy(result.packet.data()+64,records.data(),header.payload_bytes);
    result.values.resize(6*3549);
    if(dfl_v1_unpack_legacy(result.packet.data(),result.packet.size(),frame_id,confidence,result.values.data())!=0)
        throw std::runtime_error("DFL supplied C packet decoder rejected generated result");
    return result;
}
inline float dfl_compare_selected(const std::vector<float>& dense,const std::vector<float>& fused,float confidence){
    float maximum_error=0;
    for(int i=0;i<3549;++i){
        float a=dense[4*3549+i],b=dense[5*3549+i],c=fused[4*3549+i],d=fused[5*3549+i];
        if((std::max(a,b)>confidence)!=(std::max(c,d)>confidence))throw std::runtime_error("DFL selected mask mismatch");
        if(std::max(a,b)<=confidence)continue;
        if((b>a)!=(d>c)||std::abs(std::max(a,b)-std::max(c,d))>1e-5f)throw std::runtime_error("DFL class/score mismatch");
        for(int k=0;k<4;++k)maximum_error=std::max(maximum_error,std::abs(dense[k*3549+i]-fused[k*3549+i]));
    }
    if(maximum_error>.001f)throw std::runtime_error("DFL coordinate mismatch");
    return maximum_error;
}
