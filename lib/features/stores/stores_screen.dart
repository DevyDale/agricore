import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/farmland_background.dart';
import '../../widgets/state_views.dart';
import 'store_bits.dart';
import 'store_detail_sheet.dart';
import 'store_form_sheet.dart';
import '../settings/settings_screen.dart';

const Color _heroDark = Color(0xFF22432C);

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService(context.read<DioClient>().dio);
      final data = await api.list(Api.stores);
      if (!mounted) return;
      setState(() {
        _all = data;
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
                                    text: 'Stores',
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
          if (_loading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 56), child: LoadingView()))
          else if (_error != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 40), child: ErrorView(message: _error!, onRetry: _load)))
          else if (_all.isEmpty)
            const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: EmptyView(text: 'No stalls yet. Tap "Create" to set up your first stall.', icon: Icons.storefront_outlined)))
          else if (view.isEmpty)
            const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.only(top: 30), child: EmptyView(text: 'No stores match your search.', icon: Icons.search_off_rounded)))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Text('Showing ${view.length} of ${_all.length} stall${_all.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate500)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _StallCard(store: view[i], onVisit: () => showStoreDetail(context, view[i])),
                  ),
                  childCount: view.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
                  fillColor: Colors.white,
                  hintText: 'Search by store name or country…',
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

  @override
  Widget build(BuildContext context) {
    final s = store;
    final verified = s['is_verified'] == true;
    final name = pickString(s, ['name', 'store_name', 'title']) ?? 'Unnamed stall';
    final countries = normCountries(s['countries_of_operation']);
    final value = pickNum(s, ['total_value']);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onVisit,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.green, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StallAwning(verified: verified),
              // signboard
              Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF7EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Container(width: 4, height: 38, color: kStallGold),
                    const SizedBox(width: 10),
                    const StallAvatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.inkWarm)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _srow(Icons.person_rounded, pickString(s, ['owner_name']) ?? '—'),
                    _srow(Icons.email_rounded, pickString(s, ['owner_email']) ?? '—'),
                    _srow(Icons.phone_rounded, pickString(s, ['owner_phone']) ?? '—'),
                    _srow(Icons.public_rounded, countries.isEmpty ? 'Not specified' : countries.join(', ')),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDF6E3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kStallGold, style: BorderStyle.solid),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sell_rounded, size: 14, color: kStallGold),
                          const SizedBox(width: 6),
                          Text(storeValue(value),
                              style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF7A5A16))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onVisit,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_rounded, color: Colors.white, size: 17),
                            SizedBox(width: 8),
                            Text('Visit Stall',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                          ],
                        ),
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

  Widget _srow(IconData icon, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.g600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(v,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.slate600)),
          ),
        ],
      ),
    );
  }
}
