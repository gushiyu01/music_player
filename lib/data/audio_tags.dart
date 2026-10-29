import 'dart:convert';
import 'dart:typed_data';
import 'package:charset/charset.dart';

class AudioTags {
  String? title, artist, album, lyrics;
  Uint8List? cover;
  static const maxHeader = 2 * 1024 * 1024;
  static const maxLyrics = 256 * 1024;
  static const maxCover = 5 * 1024 * 1024;

  static AudioTags parse(Uint8List bytes) {
    final result = AudioTags();
    try {
      if (bytes.length >= 10 &&
          ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'ID3') {
        result._id3(bytes);
      } else if (bytes.length >= 4 &&
          ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'fLaC') {
        result._flac(bytes);
      }
    } catch (_) {
      /* Malformed or truncated metadata must not prevent playback. */
    }
    return result;
  }

  static String decodeText(List<int> bytes, {int? encoding}) {
    var start = 0;
    var little = false;
    if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254) {
      little = true;
      start = 2;
      encoding = 1;
    }
    if (bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255) {
      start = 2;
      encoding = 2;
    }
    String text;
    if (encoding == 1 || encoding == 2) {
      final units = <int>[];
      for (var i = start; i + 1 < bytes.length; i += 2) {
        units.add(
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
        );
      }
      text = String.fromCharCodes(units);
    } else if (encoding == 0) {
      text = latin1.decode(bytes);
    } else {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = gbk.decode(bytes);
      }
    }
    return text.replaceAll('\u0000', '').replaceFirst('\ufeff', '').trim();
  }

  static int _number(
    List<int> bytes,
    int start,
    int count, {
    bool sync = false,
    bool little = false,
  }) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      final part = bytes[start + (little ? count - i - 1 : i)];
      value = (value << (sync ? 7 : 8)) | (sync ? part & 127 : part);
    }
    return value;
  }

  static int _terminated(List<int> bytes, int start, int encoding) {
    final width = encoding == 1 || encoding == 2 ? 2 : 1;
    for (var i = start; i + width <= bytes.length; i += width) {
      if (bytes[i] == 0 && (width == 1 || bytes[i + 1] == 0)) return i + width;
    }
    return bytes.length;
  }

  void _id3(Uint8List bytes) {
    final version = bytes[3];
    if (version != 3 && version != 4 || bytes[5] & 0x80 != 0) return;
    final end = (10 + _number(bytes, 6, 4, sync: true)).clamp(10, bytes.length);
    var position = 10;
    if (bytes[5] & 0x40 != 0) {
      position +=
          _number(bytes, position, 4, sync: version == 4) +
          (version == 3 ? 4 : 0);
    }
    while (position + 10 <= end) {
      final id = ascii.decode(
        bytes.sublist(position, position + 4),
        allowInvalid: true,
      );
      final size = _number(bytes, position + 4, 4, sync: version == 4);
      final flags = bytes[position + 9];
      position += 10;
      if (size <= 0 || position + size > end) break;
      final data = Uint8List.sublistView(bytes, position, position + size);
      position += size;
      if (flags != 0 || data.isEmpty) continue;
      final encoding = data[0];
      if (['TIT2', 'TPE1', 'TALB'].contains(id)) {
        final text = decodeText(data.sublist(1), encoding: encoding);
        if (id == 'TIT2') title = text;
        if (id == 'TPE1') artist = text;
        if (id == 'TALB') album = text;
      } else if (id == 'USLT' && data.length > 4 && size <= maxLyrics) {
        final start = _terminated(data, 4, encoding);
        lyrics ??= decodeText(data.sublist(start), encoding: encoding);
      } else if (id == 'APIC' && data.length > 4 && size <= maxCover) {
        final typePosition = _terminated(data, 1, 0);
        if (typePosition >= data.length) continue;
        final start = _terminated(data, typePosition + 1, encoding);
        if (start < data.length && (cover == null || data[typePosition] == 3)) {
          cover = Uint8List.fromList(data.sublist(start));
        }
      }
    }
  }

  void _flac(Uint8List bytes) {
    var position = 4;
    while (position + 4 <= bytes.length) {
      final header = bytes[position];
      final type = header & 127;
      final size = _number(bytes, position + 1, 3);
      position += 4;
      if (position + size > bytes.length) return;
      final data = Uint8List.sublistView(bytes, position, position + size);
      if (type == 4) {
        var p = 4 + _number(data, 0, 4, little: true);
        final count = _number(data, p, 4, little: true);
        p += 4;
        for (var i = 0; i < count && p + 4 <= data.length; i++) {
          final length = _number(data, p, 4, little: true);
          p += 4;
          if (length > maxLyrics || p + length > data.length) break;
          final value = utf8.decode(data.sublist(p, p + length));
          p += length;
          final equal = value.indexOf('=');
          if (equal <= 0) continue;
          final key = value.substring(0, equal).toUpperCase();
          final text = value.substring(equal + 1);
          if (key == 'TITLE') title = text;
          if (key == 'ARTIST') artist = text;
          if (key == 'ALBUM') album = text;
          if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS') lyrics ??= text;
        }
      } else if (type == 6 && size <= maxCover) {
        final kind = _number(data, 0, 4);
        var p = 8 + _number(data, 4, 4);
        p += 4 + _number(data, p, 4);
        p += 16;
        final length = _number(data, p, 4);
        p += 4;
        if (p + length <= data.length &&
            length > 0 &&
            (cover == null || kind == 3)) {
          cover = Uint8List.fromList(data.sublist(p, p + length));
        }
      }
      position += size;
      if (header & 128 != 0) return;
    }
  }
}
