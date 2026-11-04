#pragma once
#include <array>
#include <cmath>
#include <stdexcept>
extern "C" {
#include "mxfp8_roi_gate.h"
}

// Arithmetic equivalent of the delivered RTL and its rule-weight loader.
// This is PS software execution, not execution of a PL IP core.
inline void roi_gate_software(const int16_t* features,Mxfp8RoiGateResult& result){
    for(int o=0;o<4;++o){
        int32_t sum=0;
        for(int i=0;i<18;++i){
            int32_t weight=0;
            if((o==0&&i==1)||(o==1&&i==2)||(o==2&&i==0)||(o==3&&i==3))weight=32767;
            if(o==2&&i==12)weight=-32768;
            int64_t product=int64_t(features[i])*weight;
            // Explicit floor division reproduces signed RTL >>>15, including
            // negative products, without relying on C++ signed-shift behavior.
            sum+=int32_t(product>=0?product/32768:-((-product+32767)/32768));
        }
        result.score[o]=sum;
    }
    for(int i=0;i<18;++i)result.feature[i]=features[i];
    result.valid=1;result.need_qwen=result.score[2]>=128;
}
