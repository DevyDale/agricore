import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/chat_api.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/log.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'chat_bits.dart';
import 'chat_models.dart';
import 'chat_room_screen.dart';
import '../settings/settings_screen.dart';
import '../../providers/auth_provider.dart';

const Color _heroDark = Color(0xFF22432C);

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ChatApi _api = ChatApi(context.read<DioClient>().dio);
  final _searchCtrl = TextEditingController();

  List<ChatConversation> _all = [];
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _tab = 'direct'; // direct | group | channel
  bool _discover = false;
  Timer? _peopleDebounce;

  static const _tabs = [
    ['direct', 'Inbox'],
    ['group', 'Groups'],
    ['channel', 'Channels'],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _peopleDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = _discover ? await _api.publicChannels(search: _query) : await _api.conversations(search: _query);
      final parsed = raw.map(ChatConversation.fromJson).toList()
        ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
      if (!mounted) return;
      setState(() {
        _all = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  List<ChatConversation> get _view {
    if (_discover) return _all;
    return _all.where((c) {
      final okTab = c.type == _tab;
      final okQ = _query.isEmpty || c.displayName.toLowerCase().contains(_query.toLowerCase());
      return okTab && okQ;
    }).toList();
  }

  void _onSearch(String v) {
    setState(() => _query = v);
    _load();
    _peopleDebounce?.cancel();
    if (v.trim().isEmpty || _discover) {
      setState(() => _people = []);
      return;
    }
    _peopleDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await _api.searchUsers(v.trim());
        if (!mounted) return;
        setState(() => _people = res);
      } catch (e) {
        logSwallowed('ConversationsScreen.searchUsers', e);
      }
    });
  }

  Future<void> _openRoom(int id, String title) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(conversationId: id, title: title)));
    _load();
  }

  Future<void> _startDirect(Map<String, dynamic> u) async {
    try {
      final d = await _api.startDirect(u['id']);
      final cc = ChatConversation.fromJson(d);
      _searchCtrl.clear();
      setState(() {
        _query = '';
        _people = [];
      });
      _openRoom(cc.id, cc.displayName.isNotEmpty ? cc.displayName : (u['username'] ?? 'Chat').toString());
    } catch (_) {
      if (mounted) showToast(context, 'Could not start chat', success: false);
    }
  }

  Future<void> _join(ChatConversation c) async {
    try {
      await _api.joinChannel(c.id);
      setState(() => _discover = false);
      await _load();
      _openRoom(c.id, c.displayName);
    } catch (_) {
      if (mounted) showToast(context, 'Could not join', success: false);
    }
  }

  Future<void> _newConversation() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewConversationSheet(),
    );
    if (result == null) return;
    try {
      final created = await _api.createConversation(result['title'] as String, result['type'] as String);
      final cc = ChatConversation.fromJson(created);
      await _load();
      _openRoom(cc.id, cc.displayName.isNotEmpty ? cc.displayName : result['title'] as String);
    } catch (_) {
      if (mounted) showToast(context, 'Could not create', success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().user?.username ?? 'there';
    final view = _view;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 190,
            toolbarHeight: 56,
            backgroundColor: _heroDark,
            foregroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            leading: IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              onPressed: _openSettings,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  FarmlandBackground(showPins: false, child: const SizedBox.expand()),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC0E2018), Color(0x800E2018)]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 56, bottom: 56),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text.rich(
                            const TextSpan(
                              style: TextStyle(
                                  fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 28, height: 1.05, color: Colors.white),
                              children: [
                                TextSpan(text: 'Your '),
                                TextSpan(
                                    text: 'Chats',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: AppColors.gold)),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text('Welcome back, $name',
                              style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 12.5, letterSpacing: 0.3, color: Colors.white.withValues(alpha: 0.9))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(56), child: _searchRow()),
          ),
          SliverToBoxAdapter(child: _chipsRow()),
          if (_people.isNotEmpty) ..._peopleSlivers(),
          if (_loading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 50), child: LoadingView()))
          else if (_error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(message: _error!, onRetry: _load)))
          else if (view.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: EmptyView(
                  text: _discover ? 'No public channels found.' : 'No conversations here yet.',
                  icon: Icons.forum_outlined,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _discover ? _discoverTile(view[i]) : _convTile(view[i]),
                  childCount: view.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  // ---- new conversation (leading) + search, inside the dark bar ----
  Widget _searchRow() {
    return Container(
      color: _heroDark,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: _newConversation,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Search chats, channels & people…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          }),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- tabs + discover toggle, light chips below the bar ----
  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ..._tabs.map((t) {
              final on = !_discover && t[0] == _tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _discover = false;
                    _tab = t[0];
                  }),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: on ? AppColors.g600 : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: on ? AppColors.g600 : AppColors.line),
                    ),
                    child: Text(t[1],
                        style: TextStyle(
                            fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.slate700)),
                  ),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _discover = !_discover);
                  _load();
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _discover ? AppColors.g600 : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _discover ? AppColors.g600 : AppColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_discover ? Icons.inbox_rounded : Icons.explore_rounded,
                          size: 14, color: _discover ? Colors.white : AppColors.slate700),
                      const SizedBox(width: 5),
                      Text(_discover ? 'My chats' : 'Discover',
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: _discover ? Colors.white : AppColors.slate700)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _peopleSlivers() {
    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('PEOPLE',
              style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.slate500)),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final u = _people[i];
              final name = (u['username'] ?? 'User').toString();
              return ListTile(
                leading: ConvAvatar(name: name, size: 38),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: TextButton(onPressed: () => _startDirect(u), child: const Text('Chat')),
                onTap: () => _startDirect(u),
              );
            },
            childCount: _people.length,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: Divider(height: 1, color: AppColors.line)),
    ];
  }

  Widget _convTile(ChatConversation c) {
    String sub;
    bool online = false;
    if (c.type == 'direct') {
      online = c.otherOnline;
      sub = online ? 'Active now' : (c.otherLastSeen != null ? 'last seen ${timeAgo(c.otherLastSeen)}' : 'offline');
    } else {
      sub = '${c.type == 'channel' ? 'Channel' : 'Group'} · ${c.participantCount} members';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        child: InkWell(
          onTap: () => _openRoom(c.id, c.displayName),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                ConvAvatar(name: c.displayName, online: online),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(c.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.inkWarm)),
                          ),
                          Text(timeAgo(c.updatedAt), style: const TextStyle(fontSize: 10.5, color: AppColors.slate500)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(sub,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: online ? const Color(0xFF16A34A) : AppColors.slate500, fontWeight: online ? FontWeight.w600 : FontWeight.w400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _discoverTile(ChatConversation c) {
    final joined = c.myRole != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ConvAvatar(name: c.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.inkWarm)),
                    Text('${c.description ?? 'Public channel'} · ${c.participantCount}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                  ],
                ),
              ),
              joined
                  ? OutlinedButton(onPressed: () => _openRoom(c.id, c.displayName), child: const Text('Open'))
                  : ElevatedButton(
                      onPressed: () => _join(c),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.g600, foregroundColor: Colors.white),
                      child: const Text('Join'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet();
  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _title = TextEditingController();
  String _type = 'group';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 14),
            const Text('Create group / channel',
                style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.inkWarm)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                hintText: 'Name',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.green)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _typeChip('group', 'Group — private'),
                const SizedBox(width: 10),
                _typeChip('channel', 'Channel — public'),
              ],
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () {
                final t = _title.text.trim();
                if (t.isEmpty) {
                  showToast(context, 'Enter a name', success: false);
                  return;
                }
                Navigator.pop(context, {'title': t, 'type': _type});
              },
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                child: const Text('Create', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final on = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFFEAF7EC) : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: on ? AppColors.g600 : AppColors.line, width: on ? 1.5 : 1),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12.5, color: on ? AppColors.g700 : AppColors.slate600)),
        ),
      ),
    );
  }
}
