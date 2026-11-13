#include "luma_native.h"
#include <array>
#include <algorithm>
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
 // A spectrum and spatial discontinuities activate every advertised control.
 // Verify actual byte differences, without duplicating the implementation math.
 std::vector<uint8_t> spectrum(64*64*4);
 for(int i=0;i<4096;i++){spectrum[i*4]=(i%16)*17;spectrum[i*4+1]=((i/16)%16)*17;spectrum[i*4+2]=(i/256)*17;spectrum[i*4+3]=i%256;}
 std::vector<float> lut;
 for(int b=0;b<2;b++)for(int g=0;g<2;g++)for(int r=0;r<2;r++){lut.push_back(r*.9f+.1f);lut.push_back(float(g));lut.push_back(b*.8f);}
 std::array<double,18> defaults={0,1,0,0,0,0,0,6500,0,1,0,0,0,0,0,.8,0,0};
 const double targets[]={1,1.5,.2,-.5,.7,.8,.6,9000,100,.3,.7,1.5,.8,.8,.25,.1,1,1};
 auto base=spectrum;h.fill(0);
 if(luma_apply(base.data(),64,64,defaults.data(),18,h.data(),lut.data(),2))return 7;
 auto changed=[&](const std::vector<uint8_t>& pixels){size_t difference=0;for(size_t i=0;i<pixels.size();i++){if(i%4==3){if(pixels[i]!=spectrum[i])return false;}else if(pixels[i]!=base[i])difference++;}return difference>0;};
 for(int i=0;i<18;i++){
   auto settings=defaults;settings[i]=targets[i];auto edited=spectrum;
   if(luma_apply(edited.data(),64,64,settings.data(),18,h.data(),lut.data(),2)||!changed(edited)){std::fprintf(stderr,"Scalar %d did not change valid pixels or damaged alpha\n",i);return 8;}
 }
 for(int i=0;i<24;i++){
   h.fill(0);h[i]=i%3==0?.07:.4;auto edited=spectrum;
   if(luma_apply(edited.data(),64,64,defaults.data(),18,h.data(),lut.data(),2)||!changed(edited)){std::fprintf(stderr,"HSL %d did not change valid pixels or damaged alpha\n",i);return 9;}
 }
 std::puts("identity, 42 active scalar controls, alpha, bounds and RAW error checks passed");return 0;
}
