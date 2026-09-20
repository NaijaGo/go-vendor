import 'package:flutter/material.dart';
import '../../services/explore_service.dart';
import '../Main/explore_comments_screen.dart';

class ExploreActivityScreen extends StatefulWidget {
  const ExploreActivityScreen({super.key});
  @override
  State<ExploreActivityScreen> createState() => _ExploreActivityScreenState();
}
class _ExploreActivityScreenState extends State<ExploreActivityScreen> {
  final _service = ExploreService();
  List<dynamic> _comments = [];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _more = false;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _service.dispose(); super.dispose(); }
  Future<void> _load({bool more = false}) async {
    if (_more || (more && _cursor == null)) return;
    setState(() { _loading = !more; _more = more; _error = null; });
    try {
      final data = await _service.request('vendor/activity', query: {if (more) 'before': _cursor!});
      if (mounted) setState(() { _comments = more ? [..._comments, ...data['comments'] as List] : data['comments'] as List; _cursor = data['nextCursor'] as String?; });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() { _loading = false; _more = false; }); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Explore conversations')),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Answer questions about your products and sponsored posts. Reactions also appear in your notifications.')),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Expanded(child: Text(_error!)), TextButton(onPressed: _load, child: const Text('Retry'))])),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load,
        child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), itemCount: _comments.length + 1,
          itemBuilder: (context, index) {
            if (index == _comments.length) return _cursor != null
              ? TextButton(onPressed: _more ? null : () => _load(more: true), child: Text(_more ? 'Loading...' : 'More conversations'))
              : Padding(padding: const EdgeInsets.all(24), child: Text(_comments.isEmpty ? 'Customer comments on your listings will appear here.' : 'You are all caught up.', textAlign: TextAlign.center));
            final comment = _comments[index];
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
              title: Text(comment['authorName']?.toString() ?? 'Customer'),
              subtitle: Text(comment['body']?.toString() ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.reply),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ExploreCommentsScreen(
                  type: comment['targetType'].toString(), itemId: comment['target'].toString(),
                  parentId: (comment['parent'] ?? comment['id']).toString(), title: 'Reply to customer')));
                if (mounted) _load();
              },
            ));
          }))),
    ]),
  );
}
