import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/log.dart';
import '../../providers/cart_model.dart';
import '../../widgets/app_toast.dart';
import 'product_bits.dart';

Future<void> showCartSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CartSheet(),
  );
}

class _CartSheet extends StatefulWidget {
  const _CartSheet();
  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  bool _busy = false;

  /// Escrow-protected checkout. Cart lines are grouped by store; each store gets
  /// its own order + items + escrow, then a hosted payment link. Amounts are
  /// authoritative on the server — we only send products and quantities.
  Future<void> _checkout(CartModel cart) async {
    final lines = cart.lines;
    if (lines.isEmpty || _busy) return;

    final groups = <String, List<CartLine>>{};
    for (final l in lines) {
      (groups[l.storeId] ??= []).add(l);
    }
    if (groups.keys.any((k) => k.isEmpty)) {
      showToast(context, 'Some items are missing store info — please remove and re-add them.',
          success: false);
      return;
    }

    setState(() => _busy = true);
    final dio = context.read<DioClient>().dio;
    final results = <_StorePayment>[];
    try {
      for (final entry in groups.entries) {
        final storeId = int.tryParse(entry.key);
        final group = entry.value;

        final orderRes = await dio.post('/orders/', data: {
          'store': storeId,
          'currency': 'UGX',
          'status': 'pending',
          'shipping_address': '',
        });
        final orderId = (orderRes.data is Map) ? orderRes.data['id'] : null;
        if (orderId == null) throw Exception('Order could not be created.');

        for (final l in group) {
          await dio.post('/order-items/', data: {
            'order': orderId,
            'product': int.tryParse(l.id),
            'quantity': l.qty,
          });
        }

        final escRes = await dio.post('/escrows/', data: {'order': orderId, 'currency': 'UGX'});
        final escId = (escRes.data is Map) ? escRes.data['id'] : null;
        if (escId == null) throw Exception('Escrow could not be created.');

        final payRes = await dio.post('/escrows/$escId/pay/');
        final link = (payRes.data is Map) ? (payRes.data['checkout_link']?.toString() ?? '') : '';
        results.add(_StorePayment(group.first.storeName, link));
      }
      if (!mounted) return;
      cart.clear();
      setState(() => _busy = false);
      await _showResult(results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, friendlyError(e), success: false);
    }
  }

  Future<void> _showResult(List<_StorePayment> payments) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CheckoutResultSheet(payments: payments),
    );
    if (mounted) Navigator.of(context).maybePop(); // close the (now empty) cart
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Consumer<CartModel>(
      builder: (context, cart, _) {
        final lines = cart.lines;
        return Container(
          constraints: BoxConstraints(maxHeight: size.height * 0.85),
          decoration: BoxDecoration(
              color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99))),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_rounded, color: AppColors.g600),
                    const SizedBox(width: 10),
                    Text('Your cart (${cart.count})',
                        style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: context.palette.ink)),
                    const Spacer(),
                    if (lines.isNotEmpty)
                      TextButton(
                          onPressed: _busy ? null : () => cart.clear(),
                          child: Text('Clear',
                              style: TextStyle(fontFamily: 'Inter', color: context.palette.muted2))),
                  ],
                ),
              ),
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
                  child: Column(
                    children: [
                      const Icon(Icons.shopping_cart_outlined, size: 44, color: Color(0xFFCBD5C5)),
                      const SizedBox(height: 12),
                      Text('Your cart is empty.',
                          style: TextStyle(fontFamily: 'Inter', color: context.palette.muted)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _line(cart, lines[i]),
                  ),
                ),
              if (lines.isNotEmpty) _footer(cart),
            ],
          ),
        );
      },
    );
  }

  Widget _line(CartModel cart, CartLine l) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.palette.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.palette.line)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 52, height: 52, child: GenThumb(title: l.title, big: false)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, color: context.palette.ink)),
                const SizedBox(height: 2),
                Text(money(l.price),
                    style: const TextStyle(
                        fontFamily: 'Inter', color: AppColors.g700, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
          _qtyBtn(Icons.remove, _busy ? null : () => cart.dec(l.id)),
          SizedBox(
              width: 28,
              child: Text('${l.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700))),
          _qtyBtn(Icons.add, _busy ? null : () => cart.inc(l.id)),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: const Color(0xFFF1F3EE), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: AppColors.g700),
      ),
    );
  }

  Widget _footer(CartModel cart) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal', style: TextStyle(fontFamily: 'Inter', color: context.palette.muted2)),
                Text(money(cart.subtotal),
                    style: const TextStyle(
                        fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.g600)),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _busy ? null : () => _checkout(cart),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Checkout (escrow)',
                              style: TextStyle(
                                  fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text('Payment is held safely in escrow until you confirm delivery.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: context.palette.muted)),
          ],
        ),
      ),
    );
  }
}

class _StorePayment {
  final String store;
  final String link;
  _StorePayment(this.store, this.link);
}

class _CheckoutResultSheet extends StatelessWidget {
  final List<_StorePayment> payments;
  const _CheckoutResultSheet({required this.payments});

  Future<void> _open(BuildContext context, String link) async {
    try {
      final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        showToast(context, 'Could not open the payment page.', success: false);
      }
    } catch (e) {
      logSwallowed('Checkout.openLink', e);
      if (context.mounted) showToast(context, 'Could not open the payment page.', success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: context.palette.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: context.palette.line, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.emeraldGrad),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('Order placed',
                  style: TextStyle(
                      fontFamily: 'Fraunces', fontWeight: FontWeight.w800, fontSize: 22, color: context.palette.ink)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                payments.length == 1
                    ? 'Complete payment to hold the funds in escrow.'
                    : 'One order per store. Complete each payment to hold the funds in escrow.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: context.palette.muted2),
              ),
            ),
            const SizedBox(height: 18),
            for (final p in payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: p.link.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: context.palette.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.palette.line)),
                        child: Row(children: [
                          Icon(Icons.schedule_rounded, size: 18, color: context.palette.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${p.store}: awaiting payment link',
                                style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 13, color: context.palette.muted2)),
                          ),
                        ]),
                      )
                    : GestureDetector(
                        onTap: () => _open(context, p.link),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                              gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Pay ${p.store}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                            const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 18),
                          ]),
                        ),
                      ),
              ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('Done',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: context.palette.muted2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
