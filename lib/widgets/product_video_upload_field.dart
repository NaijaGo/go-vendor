import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/product_video_service.dart';

class ProductVideoUploadField extends StatefulWidget {
  const ProductVideoUploadField({
    super.key,
    this.initialAssetId,
    required this.onChanged,
    required this.onReadyChanged,
  });
  final String? initialAssetId;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onReadyChanged;

  @override
  State<ProductVideoUploadField> createState() =>
      _ProductVideoUploadFieldState();
}

class _ProductVideoUploadFieldState extends State<ProductVideoUploadField>
    with WidgetsBindingObserver {
  final _service = ProductVideoService();
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _asset;
  VideoPlayerController? _player;
  XFile? _file;
  String? _mime;
  String? _error;
  String? _status;
  bool _busy = false;
  bool _picking = false;
  bool _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await _service.configuration();
      if (!mounted) return;
      setState(() {
        _config = config;
        _error = null;
        _loadingConfig = false;
      });
      if (config['enabled'] == true && widget.initialAssetId != null) {
        final asset = await _service.asset(widget.initialAssetId!);
        if (mounted) {
          setState(() {
            _asset = asset;
            _status = _assetLabel(asset);
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Video uploads are temporarily unavailable. You can still save an image-only product.';
          _loadingConfig = false;
        });
      }
    }
  }

  String _assetLabel(Map<String, dynamic> asset) => switch (asset['status']) {
    'approved' => 'Video approved',
    'rejected' => 'Video rejected: ${asset['rejectionReason'] ?? ''}',
    _ =>
      'Video uploaded - awaiting admin review. Save the product to attach it.',
  };

  Future<bool> _acknowledge() async {
    var accepted = false;
    final warnings = (_config?['warnings'] as List? ?? []).cast<String>();
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('Before you upload a product video'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < warnings.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${index + 1}. ${warnings[index]}'),
                      ),
                    CheckboxListTile(
                      value: accepted,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I understand and have permission to share this video.',
                      ),
                      onChanged: (value) =>
                          update(() => accepted = value == true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: accepted
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Choose video'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _pick() async {
    if (_busy || _picking) return;
    setState(() => _picking = true);
    VideoPlayerController? candidate;
    try {
      if (!await _acknowledge() || !mounted) return;
      final file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (file == null || !mounted) return;
      final extension = file.name.split('.').last.toLowerCase();
      final mime = {
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'webm': 'video/webm',
      }[extension];
      if (mime == null || await file.length() > (_config!['maxBytes'] as num)) {
        throw Exception(
          'Choose an MP4, MOV or WebM video no larger than 50 MB.',
        );
      }
      candidate = VideoPlayerController.file(File(file.path));
      await candidate.initialize().timeout(const Duration(seconds: 30));
      if (candidate.value.duration <= Duration.zero ||
          candidate.value.duration > const Duration(seconds: 60)) {
        throw Exception('Your video must be no longer than 60 seconds.');
      }
      await candidate.setVolume(0);
      if (!mounted) {
        await candidate.dispose();
        return;
      }
      await _player?.dispose();
      if (!mounted) {
        await candidate.dispose();
        return;
      }
      _service.resetUpload();
      setState(() {
        _file = file;
        _mime = mime;
        _player = candidate;
        _error = null;
      });
      candidate = null;
      await _upload();
    } catch (error) {
      await candidate?.dispose();
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _upload() async {
    if (_file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onReadyChanged(false);
    try {
      final asset = await _service.upload(
        _file!,
        _mime!,
        _config!['policyVersion'].toString(),
        (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _asset = asset;
        _status = _assetLabel(asset);
      });
      widget.onChanged(asset['id'].toString());
      widget.onReadyChanged(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Video upload did not finish. Retry, or remove the video to save this product without it.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await _player?.dispose();
    if (!mounted) return;
    _service.resetUpload();
    setState(() {
      _player = null;
      _file = null;
      _asset = null;
      _status = null;
      _error = null;
    });
    widget.onChanged('');
    widget.onReadyChanged(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingConfig || (_config != null && _config!['enabled'] != true)) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Product video',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Optional - up to 60 seconds / 50 MB. Videos appear to buyers after review.',
            ),
            if (_player?.value.isInitialized == true) ...[
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: _player!.value.aspectRatio,
                child: VideoPlayer(_player!),
              ),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _player!,
                builder: (_, value, _) => TextButton.icon(
                  onPressed: () =>
                      value.isPlaying ? _player!.pause() : _player!.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  label: const Text('Preview (muted)'),
                ),
              ),
            ] else if (_asset?['posterUrl'] != null)
              Image.network(
                _asset!['posterUrl'].toString(),
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.video_library_outlined),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || _picking
                      ? null
                      : (_config == null ? _load : _pick),
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(
                    _config == null ? 'Check availability' : 'Choose video',
                  ),
                ),
                if (_file != null && _error != null)
                  TextButton(
                    onPressed: _busy || _picking ? null : _upload,
                    child: const Text('Retry upload'),
                  ),
                if (_asset != null || _file != null)
                  TextButton(
                    onPressed: _busy || _picking ? null : _remove,
                    child: const Text('Remove video'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
