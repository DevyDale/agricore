import 'package:agricore/features/stores/store_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'store_bits.dart';
import 'store_form_sheet.dart';
import '../settings/settings_screen.dart';

const Color _heroDark = Color(0xFF22432C);
const Color _stallGreen = Color(0xFF2E7D46);
const Color _stallGold = Color(0xFFC49A2E);

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});
  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'all'; // all | verified | not_verified

  static const _filters = [
    ['all', 'All'],
    ['verified', 'Verified'],
    ['not_verified', 'Pending'],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>>? _cache;

  Future<void> _load() async {
    final cached = _cache;
    if (cached != null) {
      setState(() {
        _all = cached;
        _loading = false;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = ApiService(context.read<DioClient>().dio);
      final data = await api.list(Api.stores);
      if (!mounted) return;
      _cache = data;
      setState(() {
        _all = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (cached == null) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _openStore(Map<String, dynamic> s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoreDashboardScreen(store: s)));
    if (mounted) _load();
  }

  List<Map<String, dynamic>> get _view {
    return _all.where((s) {
      final hay = [
        pickString(s, ['name', 'store_name', 'title']),
        ...normCountries(s['countries_of_operation']),
      ].whereType<String>().join(' ').toLowerCase();
      final okQ = _query.isEmpty || hay.contains(_query.toLowerCase());
      final verified = s['is_verified'] == true;
      final okF = _filter == 'all' || (_filter == 'verified' && verified) || (_filter == 'not_verified' && !verified);
      return okQ && okF;
    }).toList();
  }

  Future<void> _openForm() async {
    final saved = await showStoreForm(context);
    if (saved == true) _load();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final total = _all.length;
    final verified = _all.where((s) => s['is_verified'] == true).length;

    return MaxWidthBody(
      child: RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 196,
            toolbarHeight: 56,
            backgroundColor: _heroDark,
            foregroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            leading: IconButton(
              tooltip: context.tr('Settings'),
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              onPressed: _openSettings,
            ),
            flexibleSpace: Stack(
              fit: StackFit.expand,
              children: [
                // farmland texture pattern — consistent with the app's other top bars
                RepaintBoundary(child: FarmlandBackground(showPins: false, child: const SizedBox.expand())),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x330E2018), Color(0xE60E2018)]),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final top = MediaQuery.of(context).padding.top;
                    final maxH = 196.0 + top;
                    final minH = kToolbarHeight + 56.0 + top; // collapsed = toolbar + pinned search row
                    final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
                    final titleOpacity = ((0.4 - t) / 0.4).clamp(0.0, 1.0);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // clean solid bar fades in on collapse so the pinned title stays readable
                        Positioned.fill(
                          child: IgnorePointer(child: Opacity(opacity: titleOpacity, child: const ColoredBox(color: _heroDark))),
                        ),
                        // expanded hero title + stats, fades out on collapse (sits above the pinned search)
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 64,
                          child: Opacity(opacity: t, child: _heroTitle(total, verified)),
                        ),
                        // compact title pinned next to the settings icon when collapsed
                        Positioned(
                          top: top,
                          left: 56,
                          right: 16,
                          height: kToolbarHeight,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: titleOpacity,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(context.tr('Your stores'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(56), child: _searchRow()),
          ),
          SliverToBoxAdapter(child: _chipsRow()),
          if (_loading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 56), child: LoadingView()))
          else if (_error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(message: _error!, onRetry: _load)))
          else if (_all.isEmpty)
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: EmptyView(text: context.tr('No stalls yet. Tap "Create" to set up your first stall.'), icon: Icons.storefront_outlined)))
          else if (view.isEmpty)
            SliverToBoxAdapter(
                child: Padding(padding: const EdgeInsets.only(top: 30), child: EmptyView(text: context.tr('No stores match your search.'), icon: Icons.search_off_rounded)))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Text('Showing ${view.length} of ${_all.length} stall${_all.length == 1 ? '' : 's'}',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: context.palette.muted)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _StallCard(store: view[i], onVisit: () => _openStore(view[i])),
                  ),
                  childCount: view.length,
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  // ---- expanded hero content: "Your stores" + stat line ----
  Widget _heroTitle(int total, int verified) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 27, height: 1.04, color: Colors.white),
            children: [
              TextSpan(text: '${context.tr('Your')} '),
              TextSpan(
                  text: context.tr('stores'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: Color(0xFFE3C56B))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.storefront_rounded, size: 15, color: Colors.white.withValues(alpha: 0.82)),
            const SizedBox(width: 6),
            Flexible(
              child: Text('$total stall${total == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.82))),
            ),
            const SizedBox(width: 8),
            Text('·', style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
            const SizedBox(width: 8),
            const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF9FE1CB)),
            const SizedBox(width: 6),
            Flexible(
              child: Text('$verified verified',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.82))),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Create (leading) + search, inside the dark bar ----
  Widget _searchRow() {
    return Container(
      color: _heroDark,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openForm,
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: context.palette.card,
                  hintText: context.tr('Search by store name or country…'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
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

  // ---- filter chips, on the page just BELOW the bar (light theme) ----
  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _filters.map((t) {
            final on = t[0] == _filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = t[0]),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: on ? AppColors.g600 : context.palette.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: on ? AppColors.g600 : context.palette.line),
                  ),
                  child: Text(context.tr(t[1]),
                      style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : context.palette.muted3)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StallCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onVisit;
  const _StallCard({required this.store, required this.onVisit});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'ST';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  Widget _awning(bool verified) {
    final a = verified ? _stallGold : const Color(0xFFC9C4B6);
    final b = verified ? const Color(0xFFF0DBA0) : const Color(0xFFE7E2D5);
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: ClipPath(
        clipper: const _AwningClipper(8),
        child: Row(children: List.generate(10, (i) => Expanded(child: ColoredBox(color: i.isEven ? a : b)))),
      ),
    );
  }

  Widget _statusPill(BuildContext context, bool verified) {
    final bg = verified ? const Color(0xFFDCFCE7) : const Color(0xFFFAEEDA);
    final fg = verified ? const Color(0xFF166534) : const Color(0xFF854F0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(verified ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(verified ? context.tr('Verified') : context.tr('Pending'),
            style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }

  Widget _srow(IconData icon, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 14, color: _stallGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    final verified = s['is_verified'] == true;
    final name = pickString(s, ['name', 'store_name', 'title']) ?? 'Unnamed stall';
    final countries = normCountries(s['countries_of_operation']);
    final value = pickNum(s, ['total_value']);

    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onVisit,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: verified ? _stallGreen : context.palette.line, width: verified ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _awning(verified),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: verified ? const Color(0xFFE3F0E7) : const Color(0xFFF0EEE6),
                          ),
                          child: Text(_initials(name),
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: verified ? const Color(0xFF25613A) : context.palette.muted2)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: context.palette.ink)),
                        ),
                        const SizedBox(width: 8),
                        _statusPill(context, verified),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _srow(Icons.person_rounded, pickString(s, ['owner_name']) ?? '—'),
                    _srow(Icons.email_rounded, pickString(s, ['owner_email']) ?? '—'),
                    _srow(Icons.phone_rounded, pickString(s, ['owner_phone']) ?? '—'),
                    _srow(Icons.public_rounded, countries.isEmpty ? context.tr('Not specified') : countries.join(', ')),
                    const SizedBox(height: 11),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF6E3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _stallGold),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.sell_rounded, size: 14, color: _stallGold),
                          const SizedBox(width: 6),
                          Text(storeValue(value),
                              style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF7A5A16))),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onVisit,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _stallGreen, borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.storefront_rounded, color: Colors.white, size: 17),
                          const SizedBox(width: 8),
                          Text(context.tr('Visit stall'), style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Scalloped market-awning bottom edge (rounded drapes) for the store tile header.
class _AwningClipper extends CustomClipper<Path> {
  final int scallops;
  const _AwningClipper(this.scallops);
  @override
  Path getClip(Size size) {
    final p = Path();
    final flat = size.height * 0.5;
    final w = size.width / scallops;
    p.moveTo(0, 0);
    p.lineTo(size.width, 0);
    p.lineTo(size.width, flat);
    for (int i = scallops - 1; i >= 0; i--) {
      final cx = w * i + w / 2;
      final endX = w * i;
      p.quadraticBezierTo(cx, size.height, endX, flat);
    }
    p.lineTo(0, 0);
    p.close();
    return p;
  }
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}