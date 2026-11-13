cmake_minimum_required(VERSION 3.14)
project(luma_native VERSION 0.5.0 LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(RAW_SOURCES
  libraw/src/libraw_c_api.cpp
  libraw/src/libraw_datastream.cpp
  libraw/src/decoders/canon_600.cpp
  libraw/src/decoders/crx.cpp
  libraw/src/decoders/pana8.cpp
  libraw/src/decoders/decoders_dcraw.cpp
  libraw/src/decoders/sonycc.cpp
  libraw/src/decompressors/losslessjpeg.cpp
  libraw/src/decoders/decoders_libraw_dcrdefs.cpp
  libraw/src/decoders/olympus14.cpp
  libraw/src/decoders/decoders_libraw.cpp
  libraw/src/decoders/dng.cpp
  libraw/src/decoders/fp_dng.cpp
  libraw/src/decoders/fuji_compressed.cpp
  libraw/src/decoders/generic.cpp
  libraw/src/decoders/kodak_decoders.cpp
  libraw/src/decoders/load_mfbacks.cpp
  libraw/src/decoders/smal.cpp
  libraw/src/decoders/unpack_thumb.cpp
  libraw/src/decoders/unpack.cpp
  libraw/src/demosaic/aahd_demosaic.cpp
  libraw/src/demosaic/ahd_demosaic.cpp
  libraw/src/demosaic/dcb_demosaic.cpp
  libraw/src/demosaic/dht_demosaic.cpp
  libraw/src/demosaic/misc_demosaic.cpp
  libraw/src/demosaic/xtrans_demosaic.cpp
  libraw/src/integration/dngsdk_glue.cpp
  libraw/src/integration/rawspeed_glue.cpp
  libraw/src/metadata/adobepano.cpp
  libraw/src/metadata/canon.cpp
  libraw/src/metadata/ciff.cpp
  libraw/src/metadata/cr3_parser.cpp
  libraw/src/metadata/epson.cpp
  libraw/src/metadata/exif_gps.cpp
  libraw/src/metadata/fuji.cpp
  libraw/src/metadata/identify_tools.cpp
  libraw/src/metadata/identify.cpp
  libraw/src/metadata/kodak.cpp
  libraw/src/metadata/leica.cpp
  libraw/src/metadata/makernotes.cpp
  libraw/src/metadata/mediumformat.cpp
  libraw/src/metadata/minolta.cpp
  libraw/src/metadata/misc_parsers.cpp
  libraw/src/metadata/nikon.cpp
  libraw/src/metadata/normalize_model.cpp
  libraw/src/metadata/olympus.cpp
  libraw/src/metadata/hasselblad_model.cpp
  libraw/src/metadata/p1.cpp
  libraw/src/metadata/pentax.cpp
  libraw/src/metadata/samsung.cpp
  libraw/src/metadata/sony.cpp
  libraw/src/metadata/tiff.cpp
  libraw/src/postprocessing/aspect_ratio.cpp
  libraw/src/postprocessing/dcraw_process.cpp
  libraw/src/postprocessing/mem_image.cpp
  libraw/src/postprocessing/postprocessing_aux.cpp
  libraw/src/postprocessing/postprocessing_utils_dcrdefs.cpp
  libraw/src/postprocessing/postprocessing_utils.cpp
  libraw/src/preprocessing/ext_preprocess.cpp
  libraw/src/preprocessing/raw2image.cpp
  libraw/src/preprocessing/subtract_black.cpp
  libraw/src/tables/cameralist.cpp
  libraw/src/tables/colorconst.cpp
  libraw/src/tables/colordata.cpp
  libraw/src/tables/wblists.cpp
  libraw/src/utils/curves.cpp
  libraw/src/utils/decoder_info.cpp
  libraw/src/utils/init_close_utils.cpp
  libraw/src/utils/open.cpp
  libraw/src/utils/phaseone_processing.cpp
  libraw/src/utils/read_utils.cpp
  libraw/src/utils/thumb_utils.cpp
  libraw/src/utils/utils_dcraw.cpp
  libraw/src/utils/utils_libraw.cpp
  libraw/src/write/apply_profile.cpp
  libraw/src/write/file_write.cpp
  libraw/src/write/tiff_writer.cpp
  libraw/src/x3f/x3f_parse_process.cpp
  libraw/src/x3f/x3f_utils_patched.cpp
)
add_library(luma_raw STATIC ${RAW_SOURCES})
target_include_directories(luma_raw PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/libraw")
target_compile_definitions(luma_raw PRIVATE LIBRAW_NODLL NO_LCMS NO_JASPER)
add_library(luma_native SHARED luma_native.cpp)
target_link_libraries(luma_native PRIVATE luma_raw)
target_compile_definitions(luma_native PRIVATE LIBRAW_NODLL)
if(MSVC)
 target_compile_definitions(luma_raw PRIVATE _CRT_SECURE_NO_WARNINGS LIBRAW_WIN32_CALLS NOMINMAX)
 target_compile_definitions(luma_native PRIVATE LIBRAW_WIN32_CALLS NOMINMAX)
 target_compile_options(luma_raw PRIVATE /w /O2)
 target_compile_options(luma_native PRIVATE /O2)
else()
 target_compile_options(luma_raw PRIVATE -w -O2)
 target_compile_options(luma_native PRIVATE -O3 -fvisibility=hidden)
endif()
if(ANDROID)
 target_link_options(luma_native PRIVATE "-Wl,-z,max-page-size=16384")
endif()
option(LUMA_BUILD_TESTS "Build native checks" OFF)
if(LUMA_BUILD_TESTS)
 enable_testing()
 add_executable(luma_native_test native_test.cpp)
 target_link_libraries(luma_native_test PRIVATE luma_native)
 add_test(NAME native_pixels COMMAND luma_native_test)
endif()
