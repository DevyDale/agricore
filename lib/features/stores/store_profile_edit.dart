import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fresh_kit.dart';
import 'store_bits.dart';

/// Full-screen editor for an existing store's public profile. Mirrors the
/// visual language of [showStoreForm] (FreshField-style inputs, gradient save
/// button) but adds the newer profile fields: logo, banner, business hours,
/// policies and social links.
class StoreProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> store;
  final VoidCallback? onSaved;
  const StoreProfileEditScreen({super.key, required this.store, this.onSaved});

  @override
  State<StoreProfileEditScreen> createState() => _StoreProfileEditScreenState();
}

class _StoreProfileEditScreenState extends State<StoreProfileEditScreen> {
  late final _dio = context.read<DioClient>().dio;

  late final _name = TextEditingController(text: pickString(widget.store, ['name', 'store_name', 'title']) ?? '');
  late final _description = TextEditingController(text: pickString(widget.store, ['description']) ?? '');
  late final _ownerName = TextEditingController(text: pickString(widget.store, ['owner_name']) ?? '');
  late final _ownerPhone = TextEditingController(text: pickString(widget.store, ['owner_phone']) ?? '');
  late final _ownerEmail = TextEditingController(text: pickString(widget.store, ['owner_email']) ?? '');
  late final _countries = TextEditingController(text: _countriesPrefill());
  late final _businessHours = TextEditingController(text: pickString(widget.store, ['business_hours']) ?? '');
  late final _policies = TextEditingController(text: pickString(widget.store, ['policies']) ?? '');

  // Social links — prefilled from store['social_links'] when it's a Map.
  late final _website = TextEditingController(text: _social('website'));
  late final _facebook = TextEditingController(text: _social('facebook'));
  late final _instagram = TextEditingController(text: _social('instagram'));
  late final _whatsapp = TextEditingController(text: _social('whatsapp'));
  late final _x = TextEditingController(text: _social('x'));

  final ImagePicker _picker = ImagePicker();
  String? _logoPath;
  String? _bannerPath;
  late final String? _existingLogo = pickString(widget.store, ['logo', 'logo_url']);
  late final String? _existingBanner = pickString(widget.store, ['banner', 'banner_url']);

  bool _busy = false;

  String _countriesPrefill() {
    final c = normCountries(widget.store['countries_of_operation']);
    return c.join(', ');
  }

  String _social(String key) {
    final raw = widget.store['social_links'];
    if (raw is Map) {
      final v = raw[key];
      if (v is String) return v;
    }
    return '';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _ownerName,
      _ownerPhone,
      _ownerEmail,
      _countries,
      _businessHours,
      _policies,
      _website,
      _facebook,
      _instagram,
      _whatsapp,
      _x,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
      if (x != null && mounted) setState(() => _logoPath = x.path);
    } catch (_) {/* ignore picker errors */}
  }

  Future<void> _pickBanner() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (x != null && mounted) setState(() => _bannerPath = x.path);
    } catch (_) {/* ignore picker errors */}
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);

    final id = (pickNum(widget.store, ['id']) ?? 0).toInt();
    final countries = _countries.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final social = <String, String>{};
    void add(String k, TextEditingController c) {
      final v = c.text.trim();
      if (v.isNotEmpty) social[k] = v;
    }

    add('website', _website);
    add('facebook', _facebook);
    add('instagram', _instagram);
    add('whatsapp', _whatsapp);
    add('x', _x);

    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'owner_name': _ownerName.text.trim(),
      'owner_phone': _ownerPhone.text.trim(),
      'owner_email': _ownerEmail.text.trim(),
      'countries_of_operation': countries,
      'business_hours': _businessHours.text.trim(),
      'policies': _policies.text.trim(),
      'social_links': social,
    };

    try {
      // 1) JSON fields (no images).
      await _dio.patch('/stores/$id/', data: body);

      // 2) Logo as its own multipart PATCH.
      if (_logoPath != null) {
        await _dio.patch(
          '/stores/$id/',
          data: FormData.fromMap({
            'logo': MultipartFile.fromFileSync(_logoPath!, filename: _logoPath!.split('/').last),
          }),
        );
      }

      // 3) Banner as its own multipart PATCH.
      if (_bannerPath != null) {
        await _dio.patch(
          '/stores/$id/',
          data: FormData.fromMap({
            'banner': MultipartFile.fromFileSync(_bannerPath!, filename: _bannerPath!.split('/').last),
          }),
        );
      }

      if (!mounted) return;
      showToast(context, 'Store profile updated', success: true);
      widget.onSaved?.call();
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      showToast(context, friendlyError(e), success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final storeName = pickString(widget.store, ['name', 'store_name', 'title']) ?? 'Store';

    return Scaffold(
      backgroundColor: p.surface,
      body: MaxWidthBody(
        child: Column(
          children: [
            GradientHero(
              title: 'Edit store',
              subtitle: storeName,
              icon: Icons.storefront_rounded,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  const FreshSectionHeader(title: 'Branding'),
                  const SizedBox(height: 12),
                  _imagePickerRow(
                    label: 'Logo',
                    icon: Icons.image_rounded,
                    pickedPath: _logoPath,
                    existingUrl: _existingLogo,
                    onPick: _pickLogo,
                    onRemove: () => setState(() => _logoPath = null),
                  ),
                  const SizedBox(height: 14),
                  _imagePickerRow(
                    label: 'Banner',
                    icon: Icons.panorama_rounded,
                    pickedPath: _bannerPath,
                    existingUrl: _existingBanner,
                    onPick: _pickBanner,
                    onRemove: () => setState(() => _bannerPath = null),
                  ),
                  const SizedBox(height: 22),
                  const FreshSectionHeader(title: 'Store details'),
                  const SizedBox(height: 12),
                  FreshField(controller: _name, label: 'Store name', hint: 'e.g. Green Valley Marketplace'),
                  const SizedBox(height: 14),
                  FreshField(controller: _description, label: 'Description', hint: 'What does your store offer?', lines: 3),
                  const SizedBox(height: 22),
                  const FreshSectionHeader(title: 'Owner & contact'),
                  const SizedBox(height: 12),
                  FreshField(controller: _ownerName, label: 'Owner name', hint: 'Your name'),
                  const SizedBox(height: 14),
                  FreshField(controller: _ownerPhone, label: 'Owner phone', hint: '+256 7…'),
                  const SizedBox(height: 14),
                  FreshField(controller: _ownerEmail, label: 'Owner email', hint: 'you@email.com'),
                  const SizedBox(height: 14),
                  FreshField(controller: _countries, label: 'Countries of operation', hint: 'e.g. Uganda, Kenya, Nigeria'),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text('Separate with commas',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: p.muted)),
                  ),
                  const SizedBox(height: 22),
                  const FreshSectionHeader(title: 'Hours & policies'),
                  const SizedBox(height: 12),
                  FreshField(controller: _businessHours, label: 'Business hours', hint: 'e.g. Mon-Fri 8am-5pm'),
                  const SizedBox(height: 14),
                  FreshField(controller: _policies, label: 'Policies', hint: 'Returns, shipping, refunds…', lines: 4),
                  const SizedBox(height: 22),
                  const FreshSectionHeader(title: 'Social links'),
                  const SizedBox(height: 12),
                  FreshField(controller: _website, label: 'Website', hint: 'https://…'),
                  const SizedBox(height: 14),
                  FreshField(controller: _facebook, label: 'Facebook', hint: 'facebook.com/…'),
                  const SizedBox(height: 14),
                  FreshField(controller: _instagram, label: 'Instagram', hint: '@handle or link'),
                  const SizedBox(height: 14),
                  FreshField(controller: _whatsapp, label: 'WhatsApp', hint: '+256 7…'),
                  const SizedBox(height: 14),
                  FreshField(controller: _x, label: 'X (Twitter)', hint: '@handle or link'),
                  const SizedBox(height: 26),
                  GestureDetector(
                    onTap: _busy ? null : _save,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Text('Save changes',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePickerRow({
    required String label,
    required IconData icon,
    required String? pickedPath,
    required String? existingUrl,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    final p = context.palette;
    Widget thumb;
    if (pickedPath != null) {
      thumb = Image.file(File(pickedPath), width: 64, height: 64, fit: BoxFit.cover);
    } else if (existingUrl != null && existingUrl.startsWith('http')) {
      thumb = Image.network(existingUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumbPlaceholder(icon));
    } else {
      thumb = _thumbPlaceholder(icon);
    }
    final hasPicked = pickedPath != null;
    final hasImage = hasPicked || (existingUrl?.isNotEmpty ?? false);
    final caption = hasPicked
        ? pickedPath.split('/').last
        : (existingUrl != null && existingUrl.isNotEmpty ? 'Current $label' : 'No $label selected');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label,
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: p.muted3)),
        ),
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 64, height: 64, child: thumb),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: p.muted)),
                const SizedBox(height: 8),
                Row(children: [
                  GestureDetector(
                    onTap: onPick,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: p.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: p.line)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.image_rounded, size: 16, color: AppColors.g600),
                        const SizedBox(width: 6),
                        Text(hasImage ? 'Change' : 'Add',
                            style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.g600)),
                      ]),
                    ),
                  ),
                  if (hasPicked) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        height: 40,
                        width: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: p.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: p.line)),
                        child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _thumbPlaceholder(IconData icon) => Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        color: context.palette.chipBg,
        child: Icon(icon, size: 22, color: context.palette.muted),
      );
}
