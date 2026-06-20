import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fresh_kit.dart';
import '../../widgets/state_views.dart';

const _mePath = '/transporters/me/';
const _transportersPath = '/transporters/';
const _jobsPath = '/delivery-jobs/';

/// Vehicle types accepted by the backend, with a friendly label + icon.
const _vehicleTypes = <_Vehicle>[
  _Vehicle('boda', 'Boda', Icons.two_wheeler_rounded),
  _Vehicle('pickup', 'Pickup', Icons.airport_shuttle_rounded),
  _Vehicle('truck', 'Truck', Icons.local_shipping_rounded),
  _Vehicle('taxi', 'Taxi', Icons.local_taxi_rounded),
  _Vehicle('bicycle', 'Bicycle', Icons.pedal_bike_rounded),
];

class _Vehicle {
  final String value;
  final String label;
  final IconData icon;
  const _Vehicle(this.value, this.label, this.icon);
}

String _vehicleLabel(String? value) {
  for (final v in _vehicleTypes) {
    if (v.value == value) return v.label;
  }
  return value == null || value.isEmpty ? 'Vehicle' : value;
}

IconData _vehicleIcon(String? value) {
  for (final v in _vehicleTypes) {
    if (v.value == value) return v.icon;
  }
  return Icons.local_shipping_rounded;
}

/// Transporter (rider) hub: register/edit a delivery profile, browse open
/// delivery jobs, accept them, and mark pickups. Phone-first layout sharing the
/// app's fresh-kit building blocks (gradient hero, pill segments, soft cards).
class TransporterScreen extends StatefulWidget {
  const TransporterScreen({super.key});
  @override
  State<TransporterScreen> createState() => _TransporterScreenState();
}

class _TransporterScreenState extends State<TransporterScreen> {
  bool _loading = true;
  String? _error;
  bool _registered = false;
  Map<String, dynamic>? _profile;

  int _tab = 0;
  bool _jobsLoading = false;
  String? _jobsError;
  List<Map<String, dynamic>> _openJobs = [];
  List<Map<String, dynamic>> _myJobs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final res = await dio.get(_mePath);
      if (!mounted) return;
      final data = res.data;
      setState(() {
        _profile = data is Map ? data.cast<String, dynamic>() : null;
        _registered = true;
        _loading = false;
      });
      _loadJobs();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        // Not registered yet — not an error state.
        setState(() {
          _registered = false;
          _profile = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = friendlyError(e);
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

  Future<void> _loadJobs() async {
    setState(() {
      _jobsLoading = true;
      _jobsError = null;
    });
    try {
      final dio = context.read<DioClient>().dio;
      final res = await Future.wait([
        dio.get(_jobsPath, queryParameters: {'scope': 'open'}),
        dio.get(_jobsPath, queryParameters: {'scope': 'mine_transporter'}),
      ]);
      if (!mounted) return;
      setState(() {
        _openJobs = asList(res[0].data);
        _myJobs = asList(res[1].data);
        _jobsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _jobsError = friendlyError(e);
        _jobsLoading = false;
      });
    }
  }

  Future<void> _register() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileSheet(existing: _profile),
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      if (_profile != null) {
        final id = pickNum(_profile!, ['id'])?.toInt();
        await dio.patch('$_transportersPath$id/', data: result);
      } else {
        await dio.post(_transportersPath, data: result);
      }
      if (!mounted) return;
      showToast(context, 'Transporter profile saved', success: true);
      _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _accept(Map<String, dynamic> job) async {
    final id = pickNum(job, ['id'])?.toInt();
    if (id == null) return;
    try {
      final dio = context.read<DioClient>().dio;
      await dio.post('$_jobsPath$id/accept/');
      if (!mounted) return;
      showToast(context, 'Job accepted', success: true);
      _loadJobs();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _markPickup(Map<String, dynamic> job) async {
    final id = pickNum(job, ['id'])?.toInt();
    if (id == null) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PickupSheet(),
    );
    if (code == null) return;
    if (!mounted) return;
    try {
      final dio = context.read<DioClient>().dio;
      await dio.post('$_jobsPath$id/pickup/', data: {'pickup_code': code});
      if (!mounted) return;
      showToast(context, 'Marked as picked up', success: true);
      _loadJobs();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: _loading
          ? Column(
              children: [
                GradientHero(
                  title: 'Transporter',
                  subtitle: 'Deliver & earn',
                  icon: Icons.local_shipping_rounded,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const Expanded(child: LoadingView()),
              ],
            )
          : _error != null
              ? Column(
                  children: [
                    GradientHero(
                      title: 'Transporter',
                      subtitle: 'Deliver & earn',
                      icon: Icons.local_shipping_rounded,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(child: ErrorView(message: _error!, onRetry: _load)),
                  ],
                )
              : _registered
                  ? _buildRegistered()
                  : _buildUnregistered(),
    );
  }

  // ---- Not registered ----
  Widget _buildUnregistered() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHero(
          title: 'Transporter',
          subtitle: 'Deliver & earn',
          icon: Icons.local_shipping_rounded,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE7F4EC),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: Color(0xFF0F7A4B), size: 30),
                ),
                const SizedBox(height: 14),
                const Text('Become a transporter',
                    style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppColors.inkWarm)),
                const SizedBox(height: 6),
                const Text(
                  'Register your vehicle to pick up delivery jobs from sellers, '
                  'move produce across the chain, and earn on every completed run.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.slate500),
                ),
                const SizedBox(height: 18),
                FreshPillButton(
                  icon: Icons.add_road_rounded,
                  label: 'Register as transporter',
                  onTap: _register,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Registered ----
  Widget _buildRegistered() {
    final p = _profile ?? {};
    final vt = pickString(p, ['vehicle_type']);
    final plate = pickString(p, ['vehicle_plate']) ?? '';
    final verified = p['is_verified'] == true;
    final rating = pickNum(p, ['rating_avg']);
    final ratingText = rating == null ? 'New' : rating.toStringAsFixed(1);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHero(
            title: 'Transporter',
            subtitle: '${_vehicleLabel(vt)}${plate.isEmpty ? '' : ' · $plate'}',
            icon: Icons.local_shipping_rounded,
            onBack: () => Navigator.of(context).maybePop(),
            trailing: InkWell(
              onTap: _register,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              ),
            ),
            chips: [
              HeroChip(
                  icon: verified
                      ? Icons.verified_rounded
                      : Icons.hourglass_bottom_rounded,
                  label: verified ? 'Verified' : 'Unverified'),
              HeroChip(icon: Icons.star_rounded, label: ratingText),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: SegTabs(
              tabs: const ['Open jobs', 'My jobs'],
              index: _tab,
              onTap: (i) => setState(() => _tab = i),
            ),
          ),
          if (_jobsLoading)
            const Padding(padding: EdgeInsets.only(top: 36), child: LoadingView())
          else if (_jobsError != null)
            Padding(
                padding: const EdgeInsets.only(top: 28),
                child: ErrorView(message: _jobsError!, onRetry: _loadJobs))
          else
            ..._buildJobsList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildJobsList() {
    final jobs = _tab == 0 ? _openJobs : _myJobs;
    if (jobs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: EmptyView(
            text: _tab == 0
                ? 'No open delivery jobs right now.\nPull to refresh.'
                : 'You haven\'t accepted any jobs yet.',
            icon: Icons.local_shipping_outlined,
          ),
        ),
      ];
    }
    return [
      for (final job in jobs)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _JobCard(
            job: job,
            mine: _tab == 1,
            onAccept: () => _accept(job),
            onPickup: () => _markPickup(job),
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool mine;
  final VoidCallback onAccept;
  final VoidCallback onPickup;
  const _JobCard({
    required this.job,
    required this.mine,
    required this.onAccept,
    required this.onPickup,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = pickString(job, ['pickup_location']) ?? '—';
    final drop = pickString(job, ['drop_location']) ?? '—';
    final fee = pickNum(job, ['offered_fee']);
    final currency = pickString(job, ['currency']) ?? 'UGX';
    final seller = pickString(job, ['seller_name']);
    final vtReq = pickString(job, ['vehicle_type_required']);
    final notes = pickString(job, ['notes']);
    final status = (pickString(job, ['status']) ?? 'open').toLowerCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(money(fee, code: currency),
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.inkWarm)),
              ),
              if (mine)
                _StatusBadge(status: status)
              else if (vtReq != null)
                _VehicleChip(vt: vtReq),
            ],
          ),
          const SizedBox(height: 12),
          _RouteRow(icon: Icons.trip_origin_rounded, color: AppColors.g600, text: pickup),
          const Padding(
            padding: EdgeInsets.only(left: 9, top: 2, bottom: 2),
            child: SizedBox(
              height: 14,
              child: VerticalDivider(width: 2, thickness: 2, color: AppColors.line),
            ),
          ),
          _RouteRow(icon: Icons.place_rounded, color: const Color(0xFFB15A36), text: drop),
          if (seller != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 15, color: AppColors.slate500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 12.5, color: AppColors.slate600)),
                ),
                if (mine && vtReq != null) _VehicleChip(vt: vtReq),
              ],
            ),
          ],
          if (notes != null) ...[
            const SizedBox(height: 8),
            Text(notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.slate500)),
          ],
          if (!mine) ...[
            const SizedBox(height: 14),
            _GradientButton(
                icon: Icons.check_circle_rounded, label: 'Accept', onTap: onAccept),
          ] else if (status == 'accepted') ...[
            const SizedBox(height: 14),
            _GradientButton(
                icon: Icons.inventory_2_rounded, label: 'Mark pickup', onTap: onPickup),
          ],
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: AppColors.inkWarm)),
        ),
      ],
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final String vt;
  const _VehicleChip({required this.vt});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFEAF7EC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_vehicleIcon(vt), size: 13, color: const Color(0xFF0F7A4B)),
        const SizedBox(width: 5),
        Text(_vehicleLabel(vt),
            style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: Color(0xFF0F7A4B))),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case 'accepted':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        label = 'Accepted';
        break;
      case 'picked_up':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Picked up';
        break;
      case 'delivered':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        label = 'Delivered';
        break;
      case 'cancelled':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        label = 'Cancelled';
        break;
      default:
        bg = const Color(0xFFE2E8F0);
        fg = AppColors.slate600;
        label = 'Open';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              color: fg)),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GradientButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: Colors.white)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _ProfileSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ProfileSheet({this.existing});
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late String _vehicleType =
      pickString(widget.existing ?? {}, ['vehicle_type']) ?? _vehicleTypes.first.value;
  late final _plate = TextEditingController(
      text: pickString(widget.existing ?? {}, ['vehicle_plate']) ?? '');
  late final _nationalId = TextEditingController(
      text: pickString(widget.existing ?? {}, ['national_id']) ?? '');
  late final _phone =
      TextEditingController(text: pickString(widget.existing ?? {}, ['phone']) ?? '');
  late final _serviceArea = TextEditingController(
      text: pickString(widget.existing ?? {}, ['service_area']) ?? '');
  String? _err;

  @override
  void dispose() {
    _plate.dispose();
    _nationalId.dispose();
    _phone.dispose();
    _serviceArea.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = _plate.text.trim();
    final nationalId = _nationalId.text.trim();
    final phone = _phone.text.trim();
    final area = _serviceArea.text.trim();
    if (plate.isEmpty || nationalId.isEmpty || phone.isEmpty || area.isEmpty) {
      setState(() => _err = 'Please fill in all fields.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'vehicle_type': _vehicleType,
      'vehicle_plate': plate,
      'national_id': nationalId,
      'phone': phone,
      'service_area': area,
    });
  }

  @override
  Widget build(BuildContext context) {
    return FreshSheet(
      title: widget.existing != null
          ? 'Edit transporter profile'
          : 'Register as transporter',
      error: _err,
      onSubmit: _submit,
      submitLabel: widget.existing != null ? 'Save changes' : 'Register',
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Vehicle type',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: AppColors.slate700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in _vehicleTypes)
              GestureDetector(
                onTap: () => setState(() => _vehicleType = v.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: _vehicleType == v.value ? AppColors.emeraldGrad : null,
                    color: _vehicleType == v.value ? null : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: _vehicleType == v.value
                            ? Colors.transparent
                            : AppColors.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(v.icon,
                        size: 15,
                        color: _vehicleType == v.value
                            ? Colors.white
                            : AppColors.slate600),
                    const SizedBox(width: 6),
                    Text(v.label,
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: _vehicleType == v.value
                                ? Colors.white
                                : AppColors.slate600)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FreshField(
            controller: _plate, label: 'Vehicle plate', hint: 'e.g. UBA 123A'),
        const SizedBox(height: 12),
        FreshField(
            controller: _nationalId,
            label: 'National ID',
            hint: 'National ID number'),
        const SizedBox(height: 12),
        FreshField(
            controller: _phone,
            label: 'Phone',
            hint: 'e.g. 0772123456',
            number: true),
        const SizedBox(height: 12),
        FreshField(
            controller: _serviceArea,
            label: 'Service area',
            hint: 'e.g. Kampala Central',
            lines: 2),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
class _PickupSheet extends StatefulWidget {
  const _PickupSheet();
  @override
  State<_PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_PickupSheet> {
  final _code = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _err = 'Enter the pickup code from the seller.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return FreshSheet(
      title: 'Mark pickup',
      error: _err,
      onSubmit: _submit,
      submitLabel: 'Confirm pickup',
      children: [
        const Text(
          'Ask the seller for the pickup code shown on their job, then enter it '
          'here to confirm you collected the goods.',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.slate500),
        ),
        const SizedBox(height: 14),
        FreshField(controller: _code, label: 'Pickup code', hint: 'e.g. 4821'),
      ],
    );
  }
}
