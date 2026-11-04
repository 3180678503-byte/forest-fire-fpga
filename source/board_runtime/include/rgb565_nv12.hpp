#pragma once
#include <cstdint>
#include <cstddef>
#include <stdexcept>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

// Little-endian RGB565 -> limited-range BT.601 NV12. UV is averaged over 2x2.
// Output stride is width. Input can have a larger byte stride.
namespace fmql_video {
inline void unpack565(uint16_t p,int& r,int& g,int& b) {
    r=(p>>11)&31;g=(p>>5)&63;b=p&31;
    r=(r<<3)|(r>>2);g=(g<<2)|(g>>4);b=(b<<3)|(b>>2);
}
inline void rgb565_nv12(const uint8_t* src,size_t stride,uint8_t* dst,int w,int h,bool scalar=false) {
    if(!src||!dst||w<=0||h<=0||w%2||h%2||stride<size_t(w)*2)
        throw std::invalid_argument("RGB565/NV12 requires positive even dimensions and valid stride");
    uint8_t* chroma=dst+size_t(w)*h;
    for(int y=0;y<h;y+=2) {
        const auto* a=reinterpret_cast<const uint16_t*>(src+size_t(y)*stride);
        const auto* b=reinterpret_cast<const uint16_t*>(src+size_t(y+1)*stride);
        uint8_t* ya=dst+size_t(y)*w;uint8_t* yb=ya+w;
        uint8_t* uv=chroma+size_t(y/2)*w;
        int x=0;
#if defined(__aarch64__)
        if(!scalar)for(;x+8<=w;x+=8) {
            uint16x8_t rr[2],gg[2],bb[2];
            for(int row=0;row<2;++row) {
                auto p=vld1q_u16((row?b:a)+x);
                auto r=vshrq_n_u16(p,11);
                auto g=vandq_u16(vshrq_n_u16(p,5),vdupq_n_u16(63));
                auto bl=vandq_u16(p,vdupq_n_u16(31));
                rr[row]=vorrq_u16(vshlq_n_u16(r,3),vshrq_n_u16(r,2));
                gg[row]=vorrq_u16(vshlq_n_u16(g,2),vshrq_n_u16(g,4));
                bb[row]=vorrq_u16(vshlq_n_u16(bl,3),vshrq_n_u16(bl,2));
                auto lum=vmulq_n_u16(rr[row],66);
                lum=vmlaq_n_u16(lum,gg[row],129);lum=vmlaq_n_u16(lum,bb[row],25);
                lum=vshrq_n_u16(vaddq_u16(lum,vdupq_n_u16(128)),8);
                vst1_u8((row?yb:ya)+x,vmovn_u16(vaddq_u16(lum,vdupq_n_u16(16))));
            }
            auto average=[](uint16x8_t p,uint16x8_t q) {
                auto sum=vaddq_u16(p,q);
                return vreinterpret_s16_u16(vshr_n_u16(vadd_u16(
                    vpadd_u16(vget_low_u16(sum),vget_high_u16(sum)),vdup_n_u16(2)),2));
            };
            auto r=average(rr[0],rr[1]),g=average(gg[0],gg[1]),bl=average(bb[0],bb[1]);
            auto u=vmla_n_s16(vmla_n_s16(vmul_n_s16(r,-38),g,-74),bl,112);
            auto v=vmla_n_s16(vmla_n_s16(vmul_n_s16(r,112),g,-94),bl,-18);
            u=vadd_s16(vshr_n_s16(vadd_s16(u,vdup_n_s16(128)),8),vdup_n_s16(128));
            v=vadd_s16(vshr_n_s16(vadd_s16(v,vdup_n_s16(128)),8),vdup_n_s16(128));
            auto u8=vqmovun_s16(vcombine_s16(u,u)),v8=vqmovun_s16(vcombine_s16(v,v));
            vst1_u8(uv+x,vzip_u8(u8,v8).val[0]);
        }
#else
        (void)scalar;
#endif
        for(;x<w;x+=2) {
            int sr=0,sg=0,sb=0;
            for(int dy=0;dy<2;++dy)for(int dx=0;dx<2;++dx) {
                int r,g,bl;unpack565((dy?b:a)[x+dx],r,g,bl);
                (dy?yb:ya)[x+dx]=uint8_t(((66*r+129*g+25*bl+128)>>8)+16);
                sr+=r;sg+=g;sb+=bl;
            }
            sr=(sr+2)>>2;sg=(sg+2)>>2;sb=(sb+2)>>2;
            uv[x]=uint8_t(((-38*sr-74*sg+112*sb+128)>>8)+128);
            uv[x+1]=uint8_t(((112*sr-94*sg-18*sb+128)>>8)+128);
        }
    }
}
}
