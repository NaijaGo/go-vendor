import 'package:http_parser/http_parser.dart';

MediaType imageUploadContentType({
  String? filename,
  String? path,
  String? mimeType,
}) {
  final normalizedMime = mimeType?.toLowerCase().trim();
  if (normalizedMime == 'image/jpeg' ||
      normalizedMime == 'image/jpg' ||
      normalizedMime == 'image/pjpeg') {
    return MediaType('image', 'jpeg');
  }
  if (normalizedMime == 'image/png' || normalizedMime == 'image/x-png') {
    return MediaType('image', 'png');
  }
  if (normalizedMime == 'image/webp') {
    return MediaType('image', 'webp');
  }

  final source = '${filename ?? ''} ${path ?? ''}'.toLowerCase();
  if (source.endsWith('.png')) return MediaType('image', 'png');
  if (source.endsWith('.webp')) return MediaType('image', 'webp');
  return MediaType('image', 'jpeg');
}

String imageUploadFilename({
  required String fallback,
  String? filename,
  String? path,
}) {
  final pickedName = _lastPathSegment(filename);
  if (_hasImageExtension(pickedName)) return pickedName!;

  final pathName = _lastPathSegment(path);
  if (_hasImageExtension(pathName)) return pathName!;

  return _hasImageExtension(fallback) ? fallback : '$fallback.jpg';
}

String? _lastPathSegment(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final parts = trimmed.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? trimmed : parts.last;
}

bool _hasImageExtension(String? value) {
  final lower = value?.toLowerCase();
  if (lower == null || lower.isEmpty) return false;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}
