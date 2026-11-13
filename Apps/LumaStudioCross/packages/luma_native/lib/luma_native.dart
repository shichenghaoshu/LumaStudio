library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class LumaNative {
  LumaNative() {
    final override = Platform.environment['LUMA_NATIVE_LIBRARY'];
    _lib = DynamicLibrary.open(
      override ??
          (Platform.isWindows
              ? 'luma_native.dll'
              : Platform.isMacOS
              ? 'libluma_native.dylib'
              : 'libluma_native.so'),
    );
    _apply = _lib
        .lookupFunction<
          Int32 Function(
            Pointer<Uint8>,
            Int32,
            Int32,
            Pointer<Double>,
            Int32,
            Pointer<Double>,
            Pointer<Float>,
            Int32,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            int,
            Pointer<Double>,
            int,
            Pointer<Double>,
            Pointer<Float>,
            int,
          )
        >('luma_apply');
    _raw = _lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Utf8>,
            Int32,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          Pointer<Uint8> Function(
            Pointer<Utf8>,
            int,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('luma_raw');
    _free = _lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('luma_free');
    _error = _lib
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'luma_error',
        );
  }
  late final DynamicLibrary _lib;
  late final int Function(
    Pointer<Uint8>,
    int,
    int,
    Pointer<Double>,
    int,
    Pointer<Double>,
    Pointer<Float>,
    int,
  )
  _apply;
  late final Pointer<Uint8> Function(
    Pointer<Utf8>,
    int,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  _raw;
  late final void Function(Pointer<Void>) _free;
  late final Pointer<Utf8> Function() _error;
  String get error => _error().toDartString();
  Uint8List process(
    Uint8List bytes,
    int w,
    int h,
    List<double> settings,
    List<double> hsl,
    Float32List? lut,
    int dimension,
  ) {
    final pixels = calloc<Uint8>(bytes.length),
        p = calloc<Double>(18),
        hs = calloc<Double>(24);
    final cube = lut == null
        ? nullptr.cast<Float>()
        : calloc<Float>(lut.length);
    try {
      pixels.asTypedList(bytes.length).setAll(0, bytes);
      p.asTypedList(18).setAll(0, settings);
      hs.asTypedList(24).setAll(0, hsl);
      if (lut != null) cube.asTypedList(lut.length).setAll(0, lut);
      if (_apply(pixels, w, h, p, 18, hs, cube, dimension) != 0) {
        throw StateError(error);
      }
      return Uint8List.fromList(pixels.asTypedList(bytes.length));
    } finally {
      calloc.free(pixels);
      calloc.free(p);
      calloc.free(hs);
      if (lut != null) calloc.free(cube);
    }
  }

  ({Uint8List pixels, int width, int height}) decodeRaw(String path, int edge) {
    final name = path.toNativeUtf8(), w = calloc<Int32>(), h = calloc<Int32>();
    Pointer<Uint8> data = nullptr;
    try {
      data = _raw(name, edge, w, h);
      if (data == nullptr) throw FormatException(error);
      return (
        pixels: Uint8List.fromList(data.asTypedList(w.value * h.value * 4)),
        width: w.value,
        height: h.value,
      );
    } finally {
      if (data != nullptr) _free(data.cast());
      calloc.free(name);
      calloc.free(w);
      calloc.free(h);
    }
  }
}
