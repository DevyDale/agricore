import 'package:flutter/material.dart';
import 'state_views.dart';
import '../core/utils/json_utils.dart';

/// Loads a list once, shows loading/error/empty states, and supports
/// pull-to-refresh. Used by the live list screens.
class DataList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() loader;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  final String emptyText;
  const DataList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.emptyText = 'Nothing here yet.',
  });

  @override
  State<DataList> createState() => _DataListState();
}

class _DataListState extends State<DataList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.loader());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return ErrorView(message: friendlyError(snap.error), onRetry: _refresh);
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                const SizedBox(height: 220),
                EmptyView(text: widget.emptyText),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (c, i) => widget.itemBuilder(c, items[i]),
          ),
        );
      },
    );
  }
}
