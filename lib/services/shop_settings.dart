import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pet shop where orders go by WhatsApp.
class ShopSettings extends ChangeNotifier {
  ShopSettings._();
  static final instance = ShopSettings._();

  static const _phoneKey = 'shop_whatsapp';
  static const _nameKey = 'shop_name';
  static const defaultName = 'Lo De Lalo Pet Shop';

  String _phone = '';
  String _name = defaultName;

  /// WhatsApp number with area code, e.g. "+54 9 11 1234-5678"; empty when
  /// not set (WhatsApp then lets you choose the contact).
  String get phone => _phone;
  String get name => _name;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _phone = prefs.getString(_phoneKey) ?? '';
    _name = prefs.getString(_nameKey) ?? defaultName;
    notifyListeners();
  }

  Future<void> save({required String name, required String phone}) async {
    _name = name.trim().isEmpty ? defaultName : name.trim();
    _phone = phone.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    await prefs.setString(_phoneKey, _phone);
    notifyListeners();
  }
}
