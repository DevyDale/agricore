import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import 'farm_bits.dart';

/// Returns 'edit' or 'delete' (or null if dismissed).
Future<String?> showFarmDetail(BuildContext context, Map<String, dynamic> farm) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FarmDetail(farm: farm),
  );
}

class _FarmDetail extends StatelessWidget {
  final Map<String, dynamic> farm;
  const _FarmDetail({required this.farm});

  @override
  Widget build(BuildContext context) {
    final key = farmTypeKey(pickString(farm, ['type', 'farm_type']));
    final name = pickString(farm, ['name', 'farm_name', 'title']) ?? 'Farm';
    final loc = [pickString(farm, ['city']), pickString(farm, ['state', 'province']), pickString(farm, ['country'])]
        .where((x) => x != null && x.isNotEmpty)
        .join(', ');
    final address = pickString(farm, ['address']);
    final notes = pickString(farm, ['additional_notes', 'notes']);
    final h = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.9),
      decoration: BoxDecoration(
          color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: FarmBanner(typeKey: key, height: 110),
              ),
              Positioned(right: 16, bottom: -22, child: FarmEmblem(typeKey: key, size: 52)),
              const Positioned(
                top: 12,
                right: 12,
                child: _CloseChip(),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 23, color: context.palette.ink)),
                const SizedBox(height: 4),
                if (loc.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: AppColors.g600),
                    const SizedBox(width: 5),
                    Expanded(child: Text(loc, style: TextStyle(fontFamily: 'Inter', color: context.palette.muted2, fontSize: 13.5))),
                  ]),
                const SizedBox(height: 16),
                _row(Icons.local_offer_rounded, 'Type', farmTypeLabel(key)),
                _row(Icons.straighten_rounded, 'Area', farmAreaText(farm)),
                if (address != null && address.isNotEmpty) _row(Icons.home_rounded, 'Address', address),
                if (notes != null && notes.isNotEmpty) _row(Icons.sticky_note_2_rounded, 'Notes', notes),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, 'edit'),
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(13)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_rounded, color: Colors.white, size: 17),
                            SizedBox(width: 8),
                            Text('Edit', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => Navigator.pop(context, 'delete'),
                      child: Container(
                        height: 50,
                        width: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFFCA5A5))),
                        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
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

class _CloseChip extends StatelessWidget {
  const _CloseChip();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(99)),
        child: const Icon(Icons.close, size: 17, color: Colors.white),
      ),
    );
  }
}
