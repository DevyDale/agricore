import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_toast.dart';

Future<bool?> showStoreForm(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StoreForm(),
  );
}

class _StoreForm extends StatefulWidget {
  const _StoreForm();
  @override
  State<_StoreForm> createState() => _StoreFormState();
}

class _StoreFormState extends State<_StoreForm> {
  late final _dio = context.read<DioClient>().dio;
  final _name = TextEditingController();
  late final _ownerName = TextEditingController(text: context.read<AuthProvider>().user?.username ?? '');
  late final _ownerEmail = TextEditingController(text: context.read<AuthProvider>().user?.email ?? '');
  late final _ownerPhone = TextEditingController(text: context.read<AuthProvider>().user?.phone ?? '');
  final _countries = TextEditingController();
  final _description = TextEditingController();
  bool _requestVerify = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _ownerName, _ownerEmail, _ownerPhone, _countries, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Store name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final countries = _countries.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final body = {
      'name': _name.text.trim(),
      'owner_name': _ownerName.text.trim(),
      'owner_phone': _ownerPhone.text.trim(),
      'owner_email': _ownerEmail.text.trim(),
      'description': _description.text.trim(),
      'countries_of_operation': countries,
      'is_verified': _requestVerify,
    };
    try {
      await _dio.post(Api.stores, data: body);
      if (!mounted) return;
      showToast(context, 'Store created');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _serverError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _serverError(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final m = e.response!.data as Map;
      final parts = <String>[];
      m.forEach((k, v) => parts.add('$k: ${v is List ? v.join(', ') : v}'));
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return friendlyError(e);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: h * 0.9,
        decoration: const BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  const Text('Create a store',
                      style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 21, color: AppColors.inkWarm)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close, color: AppColors.slate600)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFCA5A5))),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _label('Store name *'),
                  _field(_name, 'e.g. Green Valley Marketplace'),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Owner name'), _field(_ownerName, 'Your name')])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Owner phone'), _field(_ownerPhone, '+256 7…', phone: true)])),
                  ]),
                  const SizedBox(height: 14),
                  _label('Owner email'),
                  _field(_ownerEmail, 'you@email.com', email: true),
                  const SizedBox(height: 14),
                  _label('Countries of operation'),
                  _field(_countries, 'e.g. Uganda, Kenya, Nigeria'),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 2),
                    child: Text('Separate with commas', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.slate500)),
                  ),
                  const SizedBox(height: 14),
                  _label('Description'),
                  _field(_description, 'What does your store offer?', lines: 3),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => setState(() => _requestVerify = !_requestVerify),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                      child: Row(
                        children: [
                          Icon(_requestVerify ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: _requestVerify ? AppColors.g600 : AppColors.slate500),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Request verification',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppColors.inkWarm)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: _busy ? null : _save,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Text('Create store',
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate600)),
      );

  Widget _field(TextEditingController c, String hint, {bool email = false, bool phone = false, int lines = 1}) {
    return TextField(
      controller: c,
      keyboardType: email ? TextInputType.emailAddress : (phone ? TextInputType.phone : TextInputType.text),
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: AppColors.green)),
      ),
    );
  }
}
