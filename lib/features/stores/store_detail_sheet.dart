import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import 'store_bits.dart';

Future<void> showStoreDetail(BuildContext context, Map<String, dynamic> store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StoreDetail(store: store),
  );
}

class _StoreDetail extends StatelessWidget {
  final Map<String, dynamic> store;
  const _StoreDetail({required this.store});

  @override
  Widget build(BuildContext context) {
    final verified = store['is_verified'] == true;
    final name = pickString(store, ['name', 'store_name', 'title']) ?? 'Store';
    final countries = normCountries(store['countries_of_operation']);
    final desc = pickString(store, ['description', 'about', 'desc']);
    final value = pickNum(store, ['total_value']);
    final h = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.9),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: StallAwning(verified: verified),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const StallAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 20, color: context.palette.ink)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: context.palette.muted2)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              shrinkWrap: true,
              children: [
                _row(Icons.person_rounded, 'Owner', pickString(store, ['owner_name']) ?? '—'),
                _row(Icons.email_rounded, 'Email', pickString(store, ['owner_email']) ?? '—'),
                _row(Icons.phone_rounded, 'Phone', pickString(store, ['owner_phone']) ?? '—'),
                _row(Icons.public_rounded, 'Countries', countries.isEmpty ? 'Not specified' : countries.join(', ')),
                _row(Icons.sell_rounded, 'Store value', storeValue(value)),
                if (desc != null && desc.isNotEmpty) _row(Icons.info_rounded, 'Description', desc),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFBF7EE), borderRadius: BorderRadius.circular(12), border: Border.all(color: context.palette.line)),
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_customize_rounded, size: 16, color: context.palette.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Full store management — products, orders, ads and payouts — arrives in a later update.',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.palette.muted2)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
            child: Icon(icon, size: 16, color: AppColors.g600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.toUpperCase(),
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.slate500)),
                const SizedBox(height: 2),
                Text(v, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.inkWarm)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
