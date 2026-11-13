#pragma once
#include <stdint.h>
#ifdef _WIN32
#define LUMA_API __declspec(dllexport)
#else
#define LUMA_API __attribute__((visibility("default"))) __attribute__((used))
#endif
#ifdef __cplusplus
extern "C" {
#endif
LUMA_API int luma_apply(uint8_t*,int,int,const double*,int,const double*,const float*,int);
LUMA_API uint8_t* luma_raw(const char*,int,int*,int*);
LUMA_API void luma_free(void*);
LUMA_API const char* luma_error(void);
#ifdef __cplusplus
}
#endif
