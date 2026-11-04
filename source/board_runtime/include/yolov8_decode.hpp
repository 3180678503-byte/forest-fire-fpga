#pragma once
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
#include <stdexcept>

// Input pairs: box logits NHWC [1,H,W,64], class logits [1,H,W,2].
// Order: strides 8,16,32. Output is decoded [1,6,3549], channel-major.
inline std::vector<float> decode_yolov8_heads(const std::array<const float*,6>& heads){
    constexpr int total=3549;
    std::vector<float> output(6*total);int offset=0;
    for(int level=0;level<3;++level){
        int side=52>>level,stride=8<<level;
        auto box=heads[2*level];auto cls=heads[2*level+1];
        for(int y=0;y<side;++y)for(int x=0;x<side;++x){
            int cell=y*side+x,index=offset+cell;float d[4];
            for(int axis=0;axis<4;++axis){
                auto logits=box+cell*64+axis*16;
                float maximum=*std::max_element(logits,logits+16),sum=0,weighted=0;
                for(int bin=0;bin<16;++bin){
                    if(!std::isfinite(logits[bin]))throw std::runtime_error("Non-finite DFL logits");
                    float p=std::exp(logits[bin]-maximum);sum+=p;weighted+=p*bin;
                }
                d[axis]=weighted/sum;
            }
            output[index]=(x+.5f+(d[2]-d[0])*.5f)*stride;
            output[total+index]=(y+.5f+(d[3]-d[1])*.5f)*stride;
            output[2*total+index]=(d[0]+d[2])*stride;
            output[3*total+index]=(d[1]+d[3])*stride;
            for(int c=0;c<2;++c){
                float a=cls[cell*2+c];if(!std::isfinite(a))throw std::runtime_error("Non-finite class logits");
                output[(4+c)*total+index]=a>=0?1.f/(1.f+std::exp(-a)):std::exp(a)/(1.f+std::exp(a));
            }
        }
        offset+=side*side;
    }
    return output;
}
