import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../../services/explore_service.dart';

class ExplorePublishScreen extends StatefulWidget {
  const ExplorePublishScreen({super.key, this.showAppBar = true});
  final bool showAppBar;
  @override
  State<ExplorePublishScreen> createState() => _ExplorePublishScreenState();
}

class _ExplorePublishScreenState extends State<ExplorePublishScreen> {
  final _service = ExploreService();
  final _caption = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _products = [], _videos = [];
  XFile? _file;
  String? _productId, _error, _productError;
  bool _loading = true, _loadingMore = false, _hasMore = false;
  bool _publishing = false, _picking = false;
  String? _changingVideo;
  int _page = 0;
  int _loadVersion = 0;

  @override
  void initState() { super.initState(); _loadVideos(); _loadProducts(); }
  @override
  void dispose() { _service.dispose(); _caption.dispose(); super.dispose(); }

  Future<void> _loadProducts() async {
    try {
      final rows = await _service.myProducts();
      if (mounted) setState(() { _products = rows; _productError = null; });
    } catch (error) { if (mounted) setState(() => _productError = error.toString()); }
  }
  Future<void> _loadVideos({bool more = false}) async {
    if (_loadingMore || (more && (_loading || !_hasMore))) return;
    final version = ++_loadVersion;
    setState(() { _loading = !more; _loadingMore = more; _error = null; });
    try {
      final page = more ? _page + 1 : 1;
      final response = await _service.myVideos(page: page);
      final rows = (response['items'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
      if (mounted && version == _loadVersion) setState(() {
        _videos = more ? [..._videos, ...rows] : rows;
        _page = page; _hasMore = response['hasMore'] == true;
      });
    } catch (error) { if (mounted && version == _loadVersion) setState(() => _error = error.toString()); }
    finally { if (mounted && version == _loadVersion) setState(() { _loading = false; _loadingMore = false; }); }
  }
  Future<void> _chooseVideo({bool fromFiles = false}) async {
    if (_publishing || _picking) return;
    setState(() => _picking = true);
    try {
      XFile? file;
      if (fromFiles) {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom,
          allowedExtensions: ['mp4', 'mov', 'webm', 'm4v', '3gp', '3g2', 'avi', 'mkv', 'mpg', 'mpeg', 'wmv', 'flv']);
        if (result != null) {
          final selected = result.files.single;
          if (selected.path == null) throw const ExploreException('Download the video to your device before selecting it.');
          file = XFile(selected.path!, name: selected.name);
        }
      } else { file = await ImagePicker().pickVideo(source: ImageSource.gallery); }
      if (file == null) return;
      if (await file.length() > 90 * 1024 * 1024) throw const ExploreException('Compress this video to 90 MB or less.');
      if (mounted) setState(() { _file = file; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = error is ExploreException
          ? error.message : 'Could not select a video. Allow gallery access or try a video file.');
    } finally { if (mounted) setState(() => _picking = false); }
  }
  Future<void> _publish() async {
    if (_publishing || !_form.currentState!.validate()) return;
    if (_file == null) { setState(() => _error = 'Choose a video first.'); return; }
    setState(() { _publishing = true; _error = null; });
    try {
      final video = await _service.publishVideo(_file!, _caption.text, productId: _productId);
      if (!mounted) return;
      setState(() { _file = null; _productId = null; });
      _caption.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video published to customer Explore.')));
      // Show the real API result immediately; then refresh the authoritative list.
      setState(() => _videos.insert(0, {...video, 'status': 'published'}));
      await _loadVideos();
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _publishing = false); }
  }
  Future<void> _controlVideo(Map<String, dynamic> video, bool remove) async {
    if (_changingVideo != null) return;
    final id = (video['id'] ?? video['_id'])?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(remove ? 'Delete video?' : 'Unpublish video?'),
      content: Text(remove ? 'This removes this video from Explore.' : 'Customers will no longer see this video in Explore.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(remove ? 'Delete' : 'Unpublish'))]));
    if (confirmed != true || !mounted) return;
    setState(() => _changingVideo = id);
    try {
      if (remove) { await _service.deleteVideo(id); } else { await _service.unpublishVideo(id); }
      await _loadVideos();
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _changingVideo = null); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.showAppBar ? AppBar(title: const Text('Explore Videos')) : null,
    body: RefreshIndicator(onRefresh: () => _loadVideos(), child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const Text('Reach customers through Explore', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Publish from your approved vendor account. Product linking is optional. Share videos you have permission to publish.'),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Form(key: _form, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _publishing || _picking ? null : () => _chooseVideo(), icon: const Icon(Icons.video_library_outlined), label: const Text('Gallery')),
              TextButton.icon(onPressed: _publishing || _picking ? null : () => _chooseVideo(fromFiles: true), icon: const Icon(Icons.folder_open), label: const Text('Video file')),
            ]),
            Text(_file?.name ?? 'No video selected'),
            const Text('Up to 90 MB. No 90-second limit.'),
            const SizedBox(height: 12),
            TextFormField(controller: _caption, enabled: !_publishing, maxLength: 500, maxLines: 3,
              decoration: const InputDecoration(labelText: 'Caption', border: OutlineInputBorder()),
              validator: (value) => value == null || value.trim().isEmpty ? 'Enter a caption.' : null),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: _productId,
              decoration: const InputDecoration(labelText: 'Link your product (optional)', border: OutlineInputBorder()),
              items: [const DropdownMenuItem<String>(value: null, child: Text('No product')),
                for (final product in _products) DropdownMenuItem<String>(value: product['_id'].toString(), child: Text(product['name']?.toString() ?? 'Product', overflow: TextOverflow.ellipsis))],
              onChanged: _publishing ? null : (value) => setState(() => _productId = value)),
            if (_productError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_productError!)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _publishing || _picking ? null : _publish,
              icon: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.publish),
              label: Text(_publishing ? 'Publishing…' : 'Publish to Explore')),
          ])))),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton(onPressed: () => _loadVideos(), child: const Text('Refresh My Videos'))])),
        const SizedBox(height: 20),
        const Text('My Videos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        if (!_loading && _videos.isEmpty && _error == null) const Padding(padding: EdgeInsets.all(16), child: Text('Your published videos will appear here.')),
        for (final video in _videos) Card(child: ListTile(
          leading: const Icon(Icons.smart_display_outlined),
          title: Text(video['caption']?.toString() ?? 'Video', maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${video['status'] ?? 'published'} • ${video['likesCount'] ?? 0} likes • ${video['commentsCount'] ?? 0} comments'),
          onTap: () {
            final url = Uri.tryParse(video['videoUrl']?.toString() ?? '');
            if (url?.scheme != 'https') return;
            showDialog<void>(context: context, builder: (_) => _PublishedVideoPreview(url: url!));
          },
          trailing: PopupMenuButton<String>(enabled: _changingVideo == null,
            onSelected: (value) => _controlVideo(video, value == 'delete'), itemBuilder: (_) => [
              if (video['status'] != 'unpublished') const PopupMenuItem(value: 'unpublish', child: Text('Unpublish')),
              const PopupMenuItem(value: 'delete', child: Text('Delete'))])),
        ),
        if (_hasMore) TextButton(onPressed: _loading || _loadingMore ? null : () => _loadVideos(more: true), child: Text(_loadingMore ? 'Loading…' : 'Load more videos')),
      ])),
  );
}

class _PublishedVideoPreview extends StatefulWidget {
  const _PublishedVideoPreview({required this.url});
  final Uri url;
  @override
  State<_PublishedVideoPreview> createState() => _PublishedVideoPreviewState();
}
class _PublishedVideoPreviewState extends State<_PublishedVideoPreview> {
  late final VideoPlayerController _controller;
  bool _failed = false;
  @override
  void initState() {
    super.initState(); _controller = VideoPlayerController.networkUrl(widget.url);
    _controller.initialize().then((_) { if (mounted) setState(() {}); })
        .catchError((_) { if (mounted) setState(() => _failed = true); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Video preview'),
    content: SizedBox(width: 320, child: _failed ? const Text('Could not play this video. Please try again.')
      : !_controller.value.isInitialized ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
      : Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 300, child: Center(child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)))),
        IconButton(onPressed: () { setState(() { _controller.value.isPlaying ? _controller.pause() : _controller.play(); }); },
          icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow)),
      ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}
