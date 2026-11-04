#pragma once
#include "yolov8_post.hpp"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>

// Advisory-only localhost transport.  Never sends vehicle or actuator commands.
class ActionShadowBridge {
    int fd_=-1; sockaddr_in remote_{}; uint64_t last_reply_=0; int64_t reply_ns_=0; std::string label_;
public:
    ActionShadowBridge(){
        const char* enabled=std::getenv("FMQL_ACTION_SHADOW");
        if(!enabled||std::string(enabled)!="1")return;
        fd_=socket(AF_INET,SOCK_DGRAM,0);if(fd_<0)return;
        fcntl(fd_,F_SETFL,fcntl(fd_,F_GETFL,0)|O_NONBLOCK);fcntl(fd_,F_SETFD,FD_CLOEXEC);
        remote_.sin_family=AF_INET;remote_.sin_port=htons(18771);remote_.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    }
    ~ActionShadowBridge(){if(fd_>=0)close(fd_);}
    std::string update(const std::vector<Detection>& detections,int width,int height,uint64_t frame){
        if(fd_<0)return {};
        char response[512];for(;;){
            auto n=recv(fd_,response,sizeof(response)-1,MSG_DONTWAIT);if(n<=0)break;
            response[n]='\0';char* end=nullptr;auto seq=strtoull(response,&end,10);
            if(end&&*end==' '){char* text=nullptr;auto t=strtoll(end+1,&text,10);
                if(text&&*text==' '&&seq<=frame&&seq>=last_reply_){last_reply_=seq;reply_ns_=t;label_=text+1;}}
        }
        const Detection* selected=nullptr;float fire=0,smoke=0;
        for(const auto& d:detections){
            if(d.category==0)fire=std::max(fire,d.score);else if(d.category==1)smoke=std::max(smoke,d.score);
            if(!selected||d.score>selected->score)selected=&d;
        }
        auto ns=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
        const auto b=selected?selected->box:Box{0,0,0,0};char data[768];
        int n=snprintf(data,sizeof(data),"{\"frame\":%llu,\"mono_ns\":%lld,\"width\":%d,\"height\":%d,\"category\":%d,\"score\":%.9g,\"box\":[%.9g,%.9g,%.9g,%.9g],\"fire\":%.9g,\"smoke\":%.9g}",
            (unsigned long long)frame,(long long)ns,width,height,selected?selected->category:-1,selected?selected->score:0.f,b.x,b.y,b.x+b.width,b.y+b.height,fire,smoke);
        if(n>0&&size_t(n)<sizeof(data))sendto(fd_,data,size_t(n),MSG_DONTWAIT,(sockaddr*)&remote_,sizeof(remote_));
        return last_reply_&&frame>=last_reply_&&frame-last_reply_<=3&&ns>=reply_ns_&&ns-reply_ns_<=100000000?label_:"ACTION SHADOW WAIT";
    }
};
