// LumaStudio's small process boundary around unmodified LibRaw (CDDL-1.0 option).
#include <libraw/libraw.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>

int main(int argc, char **argv) {
    if (argc == 2 && std::string(argv[1]) == "--version") {
        std::printf("LibRaw %s\n", LibRaw::version());
        return 0;
    }
    const bool identify = argc == 3 && std::string(argv[1]) == "--identify";
    if (!identify && argc != 4) return 64;
    LibRaw decoder;
    decoder.imgdata.rawparams.max_raw_memory_mb = 512;
    const char *source = identify ? argv[2] : argv[1];
    int status = decoder.open_file(source);
    if (status != LIBRAW_SUCCESS) return 65;
    const auto &size = decoder.imgdata.sizes;
    if (static_cast<unsigned long long>(size.raw_width) * size.raw_height > 120000000ULL) return 66;
    if (identify) {
        std::printf("%u %u\n", size.width, size.height);
        return 0;
    }
    char *end = nullptr;
    const double exposure = std::strtod(argv[3], &end);
    if (!end || *end || !std::isfinite(exposure) || exposure < -5 || exposure > 5) return 64;
    if (std::ifstream(argv[2]).good()) return 73;
    auto &params = decoder.imgdata.params;
    params.use_camera_wb = 1;
    params.no_auto_bright = 1;
    params.output_bps = 16;
    params.output_tiff = 1;
    params.output_color = 1;
    params.gamm[0] = 1.0 / 2.4;
    params.gamm[1] = 12.92;
    params.bright = static_cast<float>(std::pow(2.0, exposure));
    params.user_qual = 3;
    if (decoder.unpack() != LIBRAW_SUCCESS) return 67;
    if (decoder.dcraw_process() != LIBRAW_SUCCESS) return 68;
    if (decoder.dcraw_ppm_tiff_writer(argv[2]) != LIBRAW_SUCCESS) return 74;
    return 0;
}
