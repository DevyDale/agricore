import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/log.dart';

class CartLine {
  final String id;
  final String title;
  final double price;
  final String unit;
  final String image;
  final int stock;
  final String storeName;
  int qty;
  CartLine({
    required this.id,
    required this.title,
    required this.price,
    this.unit = '',
    this.image = '',
    this.stock = 0,
    this.storeName = '',
    this.qty = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'unit': unit,
        'image': image,
        'stock': stock,
        'store_name': storeName,
        'qty': qty,
      };

  factory CartLine.fromJson(Map j) => CartLine(
        id: '${j['id']}',
        title: (j['title'] ?? 'Item').toString(),
        price: (j['price'] is num) ? (j['price'] as num).toDouble() : double.tryParse('${j['price']}') ?? 0,
        unit: (j['unit'] ?? '').toString(),
        image: (j['image'] ?? '').toString(),
        stock: (j['stock'] is num) ? (j['stock'] as num).toInt() : int.tryParse('${j['stock']}') ?? 0,
        storeName: (j['store_name'] ?? '').toString(),
        qty: (j['qty'] is num) ? (j['qty'] as num).toInt() : 1,
      );
}

class CartModel extends ChangeNotifier {
  static const _key = 'agricore_cart';
  final Map<String, CartLine> _items = {};

  Map<String, CartLine> get items => _items;
  List<CartLine> get lines => _items.values.toList();
  int get count => _items.values.fold(0, (s, i) => s + i.qty);
  double get subtotal => _items.values.fold(0.0, (s, i) => s + i.price * i.qty);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is Map) {
        _items.clear();
        m.forEach((k, v) {
          if (v is Map) _items['$k'] = CartLine.fromJson(v);
        });
        notifyListeners();
      }
    } catch (e) {
      logSwallowed('CartModel._load', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_items.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {
      logSwallowed('CartModel._save', e);
    }
  }

  /// Returns true if added, false if out of stock / at stock limit.
  bool add(Map<String, dynamic> product) {
    final id = '${product['id']}';
    final stock = (product['stock_quantity'] is num)
        ? (product['stock_quantity'] as num).toInt()
        : int.tryParse('${product['stock_quantity']}') ?? 0;
    if (stock <= 0) return false;
    final existing = _items[id];
    if (existing != null) {
      if (existing.qty >= stock) return false;
      existing.qty++;
    } else {
      _items[id] = CartLine(
        id: id,
        title: (product['title'] ?? 'Item').toString(),
        price: (product['price'] is num)
            ? (product['price'] as num).toDouble()
            : double.tryParse('${product['price']}') ?? 0,
        unit: (product['unit'] ?? '').toString(),
        image: (product['image_display'] ?? product['image'] ?? product['image_url'] ?? '').toString(),
        stock: stock,
        storeName: (product['store_name'] ?? 'Agricore Seller').toString(),
        qty: 1,
      );
    }
    _save();
    notifyListeners();
    return true;
  }

  void inc(String id) {
    final i = _items[id];
    if (i == null) return;
    if (i.qty < i.stock) {
      i.qty++;
      _save();
      notifyListeners();
    }
  }

  void dec(String id) {
    final i = _items[id];
    if (i == null) return;
    i.qty--;
    if (i.qty <= 0) _items.remove(id);
    _save();
    notifyListeners();
  }

  void remove(String id) {
    _items.remove(id);
    _save();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _save();
    notifyListeners();
  }
}
