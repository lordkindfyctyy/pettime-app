import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import 'pettime_api.dart';
import 'shop_settings.dart';

class ShopInfo {
  ShopInfo({
    required this.name,
    required this.whatsapp,
    required this.address,
    required this.catalogUrl,
    required this.lostPetsUrl,
    this.logoUrl,
  });

  final String name;

  /// Digits for wa.me; empty when the shop has none.
  final String whatsapp;
  final String address;
  final String catalogUrl;
  final String lostPetsUrl;
  final String? logoUrl;

  factory ShopInfo.fromJson(Map<String, dynamic> j) => ShopInfo(
        name: j['name'] as String? ?? ShopSettings.defaultName,
        whatsapp: j['whatsapp'] as String? ?? '',
        address: j['address'] as String? ?? '',
        catalogUrl: j['catalogUrl'] as String? ?? '',
        lostPetsUrl: j['lostPetsUrl'] as String? ?? '',
        logoUrl: j['logoUrl'] as String?,
      );
}

class ShopProduct {
  ShopProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.inStock,
    required this.byWeight,
    required this.category,
    required this.brand,
    required this.description,
    this.imageUrl,
    this.promoText = '',
  });

  final int id;
  final String name;
  final double price;
  final bool inStock;

  /// Sold by the kilo: the price is per kg.
  final bool byWeight;
  final String category;
  final String brand;
  final String description;
  final String? imageUrl;

  /// "2x1", "15% off"…; empty when it has no promotion.
  final String promoText;

  String get priceLabel =>
      byWeight ? '${formatMoney(price)} el kg' : formatMoney(price);

  factory ShopProduct.fromJson(Map<String, dynamic> j) => ShopProduct(
        id: j['id'] as int,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        inStock: j['inStock'] as bool? ?? true,
        byWeight: j['saleUnit'] == 'weight',
        category: (j['category'] as String? ?? '').trim(),
        brand: j['brand'] as String? ?? '',
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        promoText: j['promo'] == true
            ? ((j['promoText'] as String?)?.trim().isNotEmpty ?? false
                ? (j['promoText'] as String).trim()
                : 'Promo')
            : '',
      );
}

class ShopCatalog {
  ShopCatalog(this.shop, this.products);

  final ShopInfo shop;
  final List<ShopProduct> products;

  /// Categories in the order they first appear, without empty ones.
  List<String> get categories {
    final seen = <String>[];
    for (final p in products) {
      if (p.category.isNotEmpty && !seen.contains(p.category)) {
        seen.add(p.category);
      }
    }
    return seen;
  }

  factory ShopCatalog.fromJson(Map<String, dynamic> j) => ShopCatalog(
        ShopInfo.fromJson(j['shop'] as Map<String, dynamic>),
        [
          for (final p in j['products'] as List)
            ShopProduct.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// Lo De Lalo's catalog: the products loaded in SixSeven for the shop, the
/// same as its catalog on the website. The last one is kept to show it
/// without internet.
class ShopService {
  ShopService({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = ShopService();
  static const _cacheKey = 'shop_catalog_cache';

  final PetTimeApi _api;

  Future<ShopCatalog?> cached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return ShopCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Future<ShopCatalog> fetch() async {
    final res = await _api.get('shop/catalog.php');
    final catalog = ShopCatalog.fromJson(res);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(res));
    // Restock orders go to the shop's WhatsApp unless another one was set.
    final settings = ShopSettings.instance;
    if (settings.phone.isEmpty && catalog.shop.whatsapp.isNotEmpty) {
      await settings.save(name: catalog.shop.name, phone: '+${catalog.shop.whatsapp}');
    }
    return catalog;
  }
}
