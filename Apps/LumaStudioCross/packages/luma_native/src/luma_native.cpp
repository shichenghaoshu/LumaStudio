#include "luma_native.h"
#include "libraw/libraw/libraw.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#endif
namespace {
thread_local std::string error;
using RGB=std::array<float,3>;
float unit(float x){return std::clamp(x,0.f,1.f);}
RGB mix(RGB a,RGB b,float t){for(int k=0;k<3;k++)a[k]+=(b[k]-a[k])*t;return a;}
RGB sample(const float* cube,int n,RGB c){
 int l[3],h[3];float f[3];for(int k=0;k<3;k++){float v=unit(c[k])*(n-1);l[k]=int(v);h[k]=std::min(n-1,l[k]+1);f[k]=v-l[k];}
 auto at=[&](int r,int g,int b)->RGB{size_t i=(size_t(b)*n*n+g*n+r)*3;return {cube[i],cube[i+1],cube[i+2]};};
 auto row=[&](int g,int b){return mix(at(l[0],g,b),at(h[0],g,b),f[0]);};
 return mix(mix(row(l[1],l[2]),row(h[1],l[2]),f[1]),mix(row(l[1],h[2]),row(h[1],h[2]),f[1]),f[2]);
}
RGB hsv(RGB c){float hi=std::max({c[0],c[1],c[2]}),lo=std::min({c[0],c[1],c[2]}),d=hi-lo,h=0;if(d>0){if(hi==c[0])h=(c[1]-c[2])/d;else if(hi==c[1])h=(c[2]-c[0])/d+2;else h=(c[0]-c[1])/d+4;h/=6;if(h<0)h++;}return {h,hi>0?d/hi:0,hi};}
RGB rgb(RGB c){float t=(c[0]-std::floor(c[0]))*6,f=t-int(t),p=c[2]*(1-c[1]),q=c[2]*(1-f*c[1]),u=c[2]*(1-(1-f)*c[1]);switch(int(t)%6){case 0:return {c[2],u,p};case 1:return {q,c[2],p};case 2:return {p,c[2],u};case 3:return {p,q,c[2]};case 4:return {u,p,c[2]};default:return {c[2],p,q};}}
thread_local std::vector<double> previous;
thread_local std::vector<float> old_lut,cube;
void compile(const double* p,const double* hsl,const float* lut,int n){
 std::vector<double> key(p,p+18);key.insert(key.end(),hsl,hsl+24);key.push_back(n);size_t length=n?size_t(n)*n*n*3:0;
 if(key==previous&&old_lut.size()==length&&(!length||std::equal(old_lut.begin(),old_lut.end(),lut)))return;
 constexpr int N=33;cube.resize(N*N*N*3);float exposure=std::exp2(float(p[0])),warm=std::log(float(p[7])/6500)*0.24f,tint=float(p[8])/150*0.08f;
 constexpr float centers[]={0,1.f/12,1.f/6,1.f/3,.5f,2.f/3,.75f,5.f/6};
 for(int b=0;b<N;b++)for(int g=0;g<N;g++)for(int r=0;r<N;r++){
  RGB c={float(r)/(N-1),float(g)/(N-1),float(b)/(N-1)};float y=.2126f*c[0]+.7152f*c[1]+.0722f*c[2];
  float tone=float(p[3])*y*y*.35f+float(p[4])*(1-y)*(1-y)*.35f+float(p[5])*y*y*y*.18f+float(p[6])*(1-y)*(1-y)*(1-y)*.18f;
  for(auto& v:c)v=unit((v*exposure-.5f)*float(p[1])+.5f+float(p[2])+tone);
  c[0]=unit(c[0]*(1+warm));c[2]=unit(c[2]*(1-warm));c[1]=unit(c[1]*(1-tint));y=.2126f*c[0]+.7152f*c[1]+.0722f*c[2];
  float sat=float(p[9])*(1+float(p[10])*(1-(std::max({c[0],c[1],c[2]})-std::min({c[0],c[1],c[2]}))));for(auto& v:c)v=unit(y+(v-y)*sat);
  RGB h=hsv(c);float dh=0,ds=0,dl=0;for(int i=0;i<8;i++){float d=std::abs(h[0]-centers[i]),w=std::max(0.f,1-std::min(d,1-d)*6);dh+=float(hsl[i*3])*w;ds+=float(hsl[i*3+1])*w;dl+=float(hsl[i*3+2])*w;}
  h[0]+=dh;h[1]=unit(h[1]*(1+ds));h[2]=unit(h[2]+dl*.3f);c=rgb(h);if(n)c=mix(c,sample(lut,n,c),float(p[15]));
  size_t i=(b*N*N+g*N+r)*3;for(int k=0;k<3;k++)cube[i+k]=unit(c[k]);
 }
 previous=std::move(key);old_lut.clear();if(length)old_lut.assign(lut,lut+length);
}
std::vector<uint8_t> blur(const uint8_t* pixels,int w,int h,int radius){
 std::vector<uint8_t> tmp(size_t(w)*h*3),out(tmp.size());int span=radius*2+1;
 for(int y=0;y<h;y++)for(int c=0;c<3;c++){float sum=0;for(int x=-radius;x<=radius;x++)sum+=pixels[(size_t(y)*w+std::clamp(x,0,w-1))*4+c];for(int x=0;x<w;x++){tmp[(size_t(y)*w+x)*3+c]=sum/span;sum+=pixels[(size_t(y)*w+std::min(w-1,x+radius+1))*4+c]-pixels[(size_t(y)*w+std::max(0,x-radius))*4+c];}}
 for(int x=0;x<w;x++)for(int c=0;c<3;c++){float sum=0;for(int y=-radius;y<=radius;y++)sum+=tmp[(size_t(std::clamp(y,0,h-1))*w+x)*3+c];for(int y=0;y<h;y++){out[(size_t(y)*w+x)*3+c]=sum/span;sum+=tmp[(size_t(std::min(h-1,y+radius+1))*w+x)*3+c]-tmp[(size_t(std::max(0,y-radius))*w+x)*3+c];}}return out;
}
}
extern "C" {
int luma_apply(uint8_t* pixels,int w,int h,const double* p,int count,const double* hsl,const float* lut,int n){
 try{
  if(!pixels||!p||!hsl||count!=18||w<1||h<1||uint64_t(w)*h>80000000||n<0||n==1||n>65||(n&&!lut))throw std::runtime_error("Invalid image/settings");
  for(int i=0;i<18;i++)if(!std::isfinite(p[i]))throw std::runtime_error("Non-finite setting");for(int i=0;i<24;i++)if(!std::isfinite(hsl[i]))throw std::runtime_error("Non-finite HSL");
  if(p[7]<1000||p[7]>50000||std::abs(p[0])>10)throw std::runtime_error("Unsafe parameter range");
  compile(p,hsl,lut,n);size_t length=size_t(w)*h;
  for(size_t i=0;i<length;i++){RGB c=sample(cube.data(),33,{pixels[i*4]/255.f,pixels[i*4+1]/255.f,pixels[i*4+2]/255.f});for(int k=0;k<3;k++)pixels[i*4+k]=uint8_t(std::lround(unit(c[k])*255));}
  bool local=p[11]>0||p[12]>0||p[16]>0;std::vector<uint8_t> blurred;if(local)blurred=blur(pixels,w,h,std::clamp(std::min(w,h)/250,1,12));
  for(int y=0;y<h;y++)for(int x=0;x<w;x++){
   size_t i=size_t(y)*w+x;float r=pixels[i*4]/255.f,g=pixels[i*4+1]/255.f,b=pixels[i*4+2]/255.f;
   // This is a color range, not a face detector or a learned beauty model.
   float skin=(r>b*1.05f&&r>g&&r-g<.35f&&r>.18f)?std::min(1.f,(r-b)*5):0;
   float nx=(x+.5f)/w*2-1,ny=(y+.5f)/h*2-1,vignette=1-float(p[13])*unit((nx*nx+ny*ny-.1f)*.55f);
   uint32_t z=uint32_t(i)*747796405u+2891336453u;z=((z>>((z>>28u)+4u))^z)*277803737u;z=(z>>22u)^z;float grain=(float(z&65535)/65535.f-.5f)*float(p[14])*80;
   for(int k=0;k<3;k++){float v=pixels[i*4+k];if(local){float d=v-blurred[i*3+k],edge=std::max(0.f,1-std::abs(d)/35);v+=d*float(p[11])*.8f-d*edge*std::max(float(p[12])*.8f,skin*float(p[16])*.85f);}v+=skin*float(p[17])*12;pixels[i*4+k]=uint8_t(std::lround(std::clamp(v*vignette+grain,0.f,255.f)));}
  }error.clear();return 0;
 }catch(const std::exception& e){error=e.what();return -1;}catch(...){error="Native processing failed";return -1;}
}
uint8_t* luma_raw(const char* path,int edge,int* w,int* h){
 try{
  if(!path||!w||!h||edge<0)throw std::runtime_error("Invalid RAW request");LibRaw raw;raw.imgdata.rawparams.max_raw_memory_mb=768;int code;
#ifdef _WIN32
  int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,nullptr,0);if(!size)throw std::runtime_error("Invalid UTF-8 path");std::vector<wchar_t> wide(size);MultiByteToWideChar(CP_UTF8,0,path,-1,wide.data(),size);code=raw.open_file(wide.data());
#else
  code=raw.open_file(path);
#endif
  if(code)throw std::runtime_error(LibRaw::strerror(code));if(uint64_t(raw.imgdata.sizes.width)*raw.imgdata.sizes.height>80000000)throw std::runtime_error("RAW exceeds 80 MP safety limit");
  raw.imgdata.params.half_size=edge>0&&std::max(raw.imgdata.sizes.width,raw.imgdata.sizes.height)>edge*2;raw.imgdata.params.output_bps=8;raw.imgdata.params.output_color=1;raw.imgdata.params.use_camera_wb=1;raw.imgdata.params.no_auto_bright=1;raw.imgdata.params.user_qual=edge?0:3;
  if((code=raw.unpack())||(code=raw.dcraw_process()))throw std::runtime_error(LibRaw::strerror(code));
  auto* image=raw.dcraw_make_mem_image(&code);if(!image||code)throw std::runtime_error("RAW pixel conversion failed");
  if(image->bits!=8||image->colors<3){LibRaw::dcraw_clear_mem(image);throw std::runtime_error("RAW output is not RGB8");}
  size_t count=size_t(image->width)*image->height;auto* out=static_cast<uint8_t*>(std::malloc(count*4));if(!out){LibRaw::dcraw_clear_mem(image);throw std::bad_alloc();}
  for(size_t i=0;i<count;i++){for(int k=0;k<3;k++)out[i*4+k]=image->data[i*image->colors+k];out[i*4+3]=255;}*w=image->width;*h=image->height;LibRaw::dcraw_clear_mem(image);error.clear();return out;
 }catch(const std::exception& e){error=e.what();return nullptr;}catch(...){error="RAW decoding failed";return nullptr;}
}
void luma_free(void* p){std::free(p);}
const char* luma_error(){return error.c_str();}
}
