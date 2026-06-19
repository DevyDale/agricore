import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../widgets/app_toast.dart';
import 'farm_bits.dart';

Future<bool?> showFarmForm(BuildContext context, {Map<String, dynamic>? farm}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FarmForm(farm: farm),
  );
}

class _FarmForm extends StatefulWidget {
  final Map<String, dynamic>? farm;
  const _FarmForm({this.farm});
  @override
  State<_FarmForm> createState() => _FarmFormState();
}

class _FarmFormState extends State<_FarmForm> {
  late final _dio = context.read<DioClient>().dio;
  late final bool _editing = widget.farm != null;

  late final _name = TextEditingController(text: _s('name', ['name', 'farm_name', 'title']));
  late final _country = TextEditingController(text: _s('country', ['country']));
  late final _state = TextEditingController(text: _s('state', ['state', 'province']));
  late final _city = TextEditingController(text: _s('city', ['city']));
  late final _address = TextEditingController(text: _s('address', ['address']));
  late final _size = TextEditingController(text: _sizeText());
  late final _notes = TextEditingController(text: _s('notes', ['additional_notes', 'notes']));
  late String _type = _editing ? farmTypeKey(pickString(widget.farm!, ['type', 'farm_type'])) : '';
  String _unit = 'acres';

  bool _busy = false;
  String? _error;

  String _s(String _, List<String> keys) => _editing ? (pickString(widget.farm!, keys) ?? '') : '';
  String _sizeText() {
    if (!_editing) return '';
    final n = pickNum(widget.farm!, ['total_size', 'size']);
    return n == null ? '' : (n % 1 == 0 ? n.toInt().toString() : n.toString());
  }

  @override
  void initState() {
    super.initState();
    if (_editing) _unit = (pickString(widget.farm!, ['size_unit', 'unit']) ?? 'acres').toLowerCase();
  }

  @override
  void dispose() {
    for (final c in [_name, _country, _state, _city, _address, _size, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _type.isEmpty ||
        _country.text.trim().isEmpty ||
        _state.text.trim().isEmpty ||
        _city.text.trim().isEmpty) {
      setState(() => _error = 'Please fill all fields marked with *');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sizeVal = double.tryParse(_size.text.trim());
    final body = {
      'name': _name.text.trim(),
      'type': _type,
      'country': _country.text.trim(),
      'state': _state.text.trim(),
      'city': _city.text.trim(),
      'address': _address.text.trim(),
      'total_size': sizeVal,
      'size_unit': _unit,
      'additional_notes': _notes.text.trim(),
    };
    try {
      if (_editing) {
        await _dio.patch('${Api.farms}${widget.farm!['id']}/', data: body);
      } else {
        await _dio.post(Api.farms, data: body);
      }
      if (!mounted) return;
      showToast(context, _editing ? 'Farm updated' : 'Farm added');
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
      m.forEach((k, v) {
        final val = v is List ? v.join(', ') : '$v';
        parts.add('$k: $val');
      });
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
        height: h * 0.92,
        decoration: const BoxDecoration(
            color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  Text(_editing ? 'Edit farm' : 'Add a farm',
                      style: const TextStyle(
                          fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 21, color: AppColors.inkWarm)),
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
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCA5A5))),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _label('Farm name *'),
                  _field(_name, 'e.g. Green Acres'),
                  const SizedBox(height: 14),
                  _label('Farm type *'),
                  Wrap(
                    spacing: 8,
                    children: ['crops', 'livestock', 'mixed']
                        .map((k) => _typeChip(k))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Country *'), _field(_country, 'Country')])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('State / Province *'), _field(_state, 'State')])),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('City *'), _field(_city, 'City')])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Address'), _field(_address, 'Street address')])),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Total size'), _field(_size, 'e.g. 150', number: true)])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_label('Unit'), _unitField()])),
                  ]),
                  const SizedBox(height: 14),
                  _label('Additional notes'),
                  _field(_notes, 'Soil type, main crops, livestock…', lines: 3),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: _busy ? null : _save,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Text(_editing ? 'Save changes' : 'Add farm',
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
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
        child: Text(t,
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.slate600)),
      );

  Widget _field(TextEditingController c, String hint, {bool number = false, int lines = 1}) {
    return TextField(
      controller: c,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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

  Widget _unitField() {
    const items = {'acres': 'acres', 'hectares': 'hectares', 'square_meters': 'square meters'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: AppColors.line)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _unit,
          isExpanded: true,
          isDense: true,
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.inkWarm),
          items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => _unit = v ?? 'acres'),
        ),
      ),
    );
  }

  Widget _typeChip(String key) {
    final on = _type == key;
    final c = farmTypeColor(key);
    return GestureDetector(
      onTap: () => setState(() => _type = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(farmTypeIcon(key), size: 14, color: on ? Colors.white : c),
            const SizedBox(width: 6),
            Text(farmTypeLabel(key),
                style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: on ? Colors.white : AppColors.slate700)),
          ],
        ),
      ),
    );
  }
}
