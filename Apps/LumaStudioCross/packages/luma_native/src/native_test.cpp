#include "luma_native.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <vector>
int main(){
 std::array<double,18> p={0,1,0,0,0,0,0,6500,0,1,0,0,0,0,0,.8,0,0};std::array<double,24> h={};std::vector<uint8_t> pixels(48*32*4);
 for(size_t i=0;i<pixels.size()/4;i++){pixels[i*4]=i%256;pixels[i*4+1]=(i/7)%256;pixels[i*4+2]=(i/13)%256;pixels[i*4+3]=255;}auto source=pixels;
 if(luma_apply(pixels.data(),48,32,p.data(),18,h.data(),nullptr,0))return 1;
 for(size_t i=0;i<pixels.size();i++)if(std::abs(int(pixels[i])-int(source[i]))>1)return 2;
 p[0]=1;if(luma_apply(pixels.data(),48,32,p.data(),18,h.data(),nullptr,0)||pixels[80*4]<=source[80*4])return 3;
 if(luma_apply(pixels.data(),48,32,p.data(),17,h.data(),nullptr,0)!=-1)return 4;
 p[0]=0;p[11]=1;p[12]=.4;p[16]=.5;p[13]=.6;if(luma_apply(pixels.data(),48,32,p.data(),18,h.data(),nullptr,0))return 5;
 int w=0,height=0;if(luma_raw("no-such-file",1600,&w,&height))return 6;
 std::puts("native identity, exposure, detail, bounds and RAW error checks passed");return 0;
}
