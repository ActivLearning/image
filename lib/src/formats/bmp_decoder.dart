import 'dart:math';

import '../animation.dart';
import '../image.dart';
import '../util/input_buffer.dart';
import 'decoder.dart';
import 'bmp/bmp_info.dart';

class BitColor {
  int b;
  int g;
  int r;
  int reserved;
  BitColor(this.b, this.g, this.r);
  int toColorInt() {
    return 0xff << 24 | b << 16 | g << 8 | r;
  }
}

BitColor getColor8FromPalette(int color) =>
    BitColor(color & 0xff, (color >> 8) & 0xff, (color >> 16) & 0xff);

class Palette {
  final List<BitColor> _colors = [];
  Palette(InputBuffer buffer, num paletteColorTotal) {
    while (paletteColorTotal > 0) {
      final bitColors = buffer.readInt32();
      _colors.add(getColor8FromPalette(bitColors));
      paletteColorTotal--;
    }
  }
  BitColor operator [](int index) {
    if (index < 0 || index >= _colors.length) {
      return BitColor(0xff, 0xff, 0xff);
    }
    return _colors[index];
  }
}

class BmpDecoder extends Decoder {
  InputBuffer _input;
  BmpInfo info;

  ///this color will be set to transparent.
  final int transparentColor;
  Palette _palette;

  BmpDecoder({this.transparentColor});

  /// Is the given file a valid BMP image?
  @override
  bool isValidFile(List<int> data) {
    return BitmapFileHeader.isValidFile(InputBuffer(data));
  }

  @override
  int numFrames() => info != null ? info.numFrames : 0;

  @override
  BmpInfo startDecode(List<int> bytes) {
    if (!isValidFile(bytes)) return null;
    _input = InputBuffer(bytes);
    info = BmpInfo(_input);
    if (info.bpp < 24) {
      _palette = Palette(_input, pow(2, info.bpp));
    }
    return info;
  }

  /// Decode a single frame from the data stat was set with [startDecode].
  /// If [frame] is out of the range of available frames, null is returned.
  /// Non animated image files will only have [frame] 0. An [AnimationFrame]
  /// is returned, which provides the image, and top-left coordinates of the
  /// image, as animated frames may only occupy a subset of the canvas.
  @override
  Image decodeFrame(int frame) {
    _input.offset = info.file.offset;
    var bytesPerPixel = info.bpp >> 3;
    var rowStride = (info.width * bytesPerPixel);
    while (rowStride % 4 != 0) {
      rowStride++;
    }

    var image = Image(info.width, info.height, channels: Channels.rgb);

    for (var y = image.height - 1; y >= 0; --y) {
      var line = info.readBottomUp ? y : image.height - 1 - y;
      var row = _input.readBytes(rowStride);
      for (var x = 0; x < image.width; ++x) {
        int color;
        if (info.bpp >= 16) {
          color = info.decodeRgba(row);
        } else {
          color = _palette[info.decodeRgba(row)].toColorInt();
          if (transparentColor != null && color == transparentColor) {
            color &= 0x00ffffff;
          }
        }
        image.setPixel(x, line, color);
      }
    }

    return image;
  }

  /// Decode the file and extract a single image from it. If the file is
  /// animated, the specified [frame] will be decoded. If there was a problem
  /// decoding the file, null is returned.
  @override
  Image decodeImage(List<int> data, {int frame = 0}) {
    if (!isValidFile(data)) return null;
    startDecode(data);
    return decodeFrame(frame);
  }

  /// Decode all of the frames from an animation. If the file is not an
  /// animation, a single frame animation is returned. If there was a problem
  /// decoding the file, null is returned.
  @override
  Animation decodeAnimation(List<int> data) {
    if (!isValidFile(data)) return null;
    var image = decodeImage(data);

    var anim = Animation();
    anim.width = image.width;
    anim.height = image.height;
    anim.addFrame(image);

    return anim;
  }
}
