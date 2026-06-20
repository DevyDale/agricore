import 'package:flutter/foundation.dart';

/// A UI action the backend can attach to a Dale reply (mirrors the web
/// dale_ai.js action protocol: navigate / show_cart / show_message /
/// filter_products).
class DaleAction {
  final String type;
  final String? target;
  final String? message;
  final List<int> productIds;

  const DaleAction({
    required this.type,
    this.target,
    this.message,
    this.productIds = const [],
  });

  static DaleAction? fromJson(dynamic j) {
    if (j is! Map) return null;
    final type = j['type']?.toString();
    if (type == null || type.isEmpty) return null;
    final ids = <int>[];
    final raw = j['product_ids'];
    if (raw is List) {
      for (final x in raw) {
        final n = int.tryParse('$x');
        if (n != null) ids.add(n);
      }
    }
    return DaleAction(
      type: type,
      target: j['target']?.toString(),
      message: j['message']?.toString(),
      productIds: ids,
    );
  }
}

/// A parsed reply from `/ai/dale/ask/`.
class DaleReply {
  final String reply;
  final DaleAction? action;
  const DaleReply(this.reply, this.action);
}

/// Bridges Dale's UI actions to the dashboard shell. The shell registers
/// handlers and keeps [currentPage] up to date; Dale reads the page for context
/// and asks the controller to carry out navigation actions.
class DaleController extends ChangeNotifier {
  /// The web-style page key for the section the user is currently viewing
  /// (e.g. 'marketplace', 'farms', 'digital_store'). Sent to the backend so
  /// Dale can tailor its answer to the screen.
  String currentPage = 'dashboard';

  /// Registered by the shell: switch the main bottom-nav/rail tab.
  void Function(int tabIndex)? onSelectTab;

  static const Map<String, int> _sectionIndex = {
    'marketplace': 0,
    'market': 0,
    'multi_farm': 1,
    'multifarm': 1,
    'farms': 1,
    'farm': 1,
    'digital_store': 2,
    'digitalstore': 2,
    'digitalstores': 2,
    'stores': 2,
    'store': 2,
    'chats': 3,
    'chat': 3,
    'messages': 3,
    'message': 3,
    'workforce': 4,
    'professional': 4,
    'wallet': 5,
    'payout': 5,
    'finance': 5,
    'finances': 5,
    'profile': 6,
  };

  void setPage(String page) => currentPage = page;

  /// Attempts to carry out [action]. Returns a short confirmation string when it
  /// did something the user should be told about, otherwise null.
  String? handle(DaleAction action) {
    switch (action.type) {
      case 'navigate':
        final idx = _indexFor(action.target ?? '');
        if (idx != null) {
          onSelectTab?.call(idx);
          return 'Opening ${_labelFor(idx)}…';
        }
        return null;
      case 'show_cart':
        onSelectTab?.call(0);
        return 'Opening the Market…';
      case 'filter_products':
        onSelectTab?.call(0);
        return action.productIds.isEmpty ? null : 'Showing the matching products on the Market…';
      default:
        return null;
    }
  }

  int? _indexFor(String target) {
    final t = target.toLowerCase();
    for (final e in _sectionIndex.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return null;
  }

  String _labelFor(int idx) {
    const labels = [
      'Market',
      'Farms',
      'Stores',
      'Chats',
      'Workforce',
      'Wallet',
      'Profile',
    ];
    return (idx >= 0 && idx < labels.length) ? labels[idx] : 'that section';
  }
}
