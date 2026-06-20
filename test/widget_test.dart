import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agricore/providers/cart_model.dart';

/// Tests for the cart that powers escrow checkout: the store id and price must
/// be captured per product, and lines must group cleanly by store (one order /
/// escrow per store at checkout).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add() captures store id, product id and price', () {
    final cart = CartModel();
    final ok = cart.add({
      'id': 7,
      'title': 'Maize',
      'price': 25000,
      'stock_quantity': 10,
      'store': 3,
      'store_name': 'Acme Farms',
    });
    expect(ok, isTrue);
    expect(cart.lines.length, 1);
    final line = cart.lines.first;
    expect(line.id, '7');
    expect(line.storeId, '3');
    expect(line.price, 25000);
    expect(line.storeName, 'Acme Farms');
  });

  test('out-of-stock products are rejected', () {
    final cart = CartModel();
    final ok = cart.add({'id': 1, 'title': 'X', 'price': 10, 'stock_quantity': 0, 'store': 1});
    expect(ok, isFalse);
    expect(cart.lines, isEmpty);
  });

  test('lines group by store id (checkout creates one order per store)', () {
    final cart = CartModel();
    cart.add({'id': 1, 'title': 'A', 'price': 10, 'stock_quantity': 5, 'store': 1});
    cart.add({'id': 2, 'title': 'B', 'price': 20, 'stock_quantity': 5, 'store': 2});
    cart.add({'id': 3, 'title': 'C', 'price': 30, 'stock_quantity': 5, 'store': 1});

    final groups = <String, List<CartLine>>{};
    for (final l in cart.lines) {
      (groups[l.storeId] ??= []).add(l);
    }
    expect(groups.keys.toSet(), {'1', '2'});
    expect(groups['1']!.length, 2);
    expect(groups['2']!.length, 1);
  });

  test('subtotal sums price x quantity', () {
    final cart = CartModel();
    cart.add({'id': 1, 'title': 'A', 'price': 10, 'stock_quantity': 5, 'store': 1});
    cart.inc('1'); // qty -> 2
    expect(cart.subtotal, 20);
  });

  test('store id survives JSON round-trip', () {
    final line = CartLine(id: '5', title: 'Beans', price: 4000, storeId: '9', storeName: 'Z');
    final back = CartLine.fromJson(line.toJson());
    expect(back.storeId, '9');
    expect(back.id, '5');
  });
}
