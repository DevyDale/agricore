import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
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

class _CartSheet extends StatelessWidget {
  const _CartSheet();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Consumer<CartModel>(
      builder: (context, cart, _) {
        final lines = cart.lines;
        return Container(
          constraints: BoxConstraints(maxHeight: size.height * 0.85),
          decoration: const BoxDecoration(
              color: AppColors.cream, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99))),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_rounded, color: AppColors.g600),
                    const SizedBox(width: 10),
                    Text('Your cart (${cart.count})',
                        style: const TextStyle(
                            fontFamily: 'Fraunces',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: AppColors.inkWarm)),
                    const Spacer(),
                    if (lines.isNotEmpty)
                      TextButton(
                          onPressed: () => cart.clear(),
                          child: const Text('Clear',
                              style: TextStyle(fontFamily: 'Inter', color: AppColors.slate600))),
                  ],
                ),
              ),
              if (lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 30, 20, 50),
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 44, color: Color(0xFFCBD5C5)),
                      SizedBox(height: 12),
                      Text('Your cart is empty.',
                          style: TextStyle(fontFamily: 'Inter', color: AppColors.slate500)),
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
                    itemBuilder: (_, i) => _line(context, cart, lines[i]),
                  ),
                ),
              if (lines.isNotEmpty) _footer(context, cart),
            ],
          ),
        );
      },
    );
  }

  Widget _line(BuildContext context, CartModel cart, CartLine l) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: GenThumb(title: l.title, big: false),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppColors.inkWarm)),
                const SizedBox(height: 2),
                Text(money(l.price),
                    style: const TextStyle(
                        fontFamily: 'Inter', color: AppColors.g700, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          ),
          _qtyBtn(Icons.remove, () => cart.dec(l.id)),
          SizedBox(
              width: 28,
              child: Text('${l.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700))),
          _qtyBtn(Icons.add, () => cart.inc(l.id)),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: const Color(0xFFF1F3EE), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: AppColors.g700),
      ),
    );
  }

  Widget _footer(BuildContext context, CartModel cart) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal',
                    style: TextStyle(fontFamily: 'Inter', color: AppColors.slate600)),
                Text(money(cart.subtotal),
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: AppColors.g600)),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => showToast(
                  context, 'Escrow-protected checkout arrives in the payments phase.'),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(gradient: AppColors.emeraldGrad, borderRadius: BorderRadius.circular(14)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Checkout (escrow)',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Payment held safely until you confirm delivery.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.slate500)),
          ],
        ),
      ),
    );
  }
}
