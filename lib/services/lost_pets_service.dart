import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lost_report.dart';
import 'pettime_api.dart';

/// Lost & found notices on sixsevenweb.com. The ones published from this
/// phone are remembered with their key, to mark them as solved or delete
/// them (there are no accounts).
class LostPetsService extends ChangeNotifier {
  LostPetsService({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = LostPetsService();

  static const _mineKey = 'lost_reports_mine';
  static const _contactKey = 'lost_reports_contact';

  final PetTimeApi _api;

  /// Report id -> its edit key.
  Map<int, String> _mine = {};

  bool isMine(int id) => _mine.containsKey(id);
  List<int> get myIds => _mine.keys.toList();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mineKey);
    if (raw != null) {
      _mine = {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          int.parse(key): value as String,
      };
    }
    notifyListeners();
  }

  Future<void> _saveMine() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mineKey,
      jsonEncode({for (final e in _mine.entries) '${e.key}': e.value}),
    );
    notifyListeners();
  }

  /// The active notices, newest first ([kind] null: both kinds).
  Future<List<LostReport>> list({ReportKind? kind}) async {
    final res = await _api.get(
      'reports/list.php',
      kind == null ? null : {'kind': kind.name},
    );
    return [
      for (final r in res['reports'] as List)
        LostReport.fromJson(r as Map<String, dynamic>),
    ];
  }

  /// The ones published from this phone, solved ones too.
  Future<List<LostReport>> mine() async {
    if (_mine.isEmpty) return [];
    final res = await _api.get('reports/list.php', {'ids': myIds.join(',')});
    final reports = [
      for (final r in res['reports'] as List)
        LostReport.fromJson(r as Map<String, dynamic>),
    ];
    // The ones that are no longer on the server (deleted) are forgotten.
    final gone = myIds.where((id) => !reports.any((r) => r.id == id)).toList();
    if (gone.isNotEmpty) {
      gone.forEach(_mine.remove);
      await _saveMine();
    }
    return reports;
  }

  Future<LostReport> publish(ReportDraft draft, List<File> photos) async {
    final res = await _api.upload(
      'reports/create.php',
      fields: draft.toFields(),
      files: {'photos[]': photos},
    );
    final report =
        LostReport.fromJson(res['report'] as Map<String, dynamic>);
    _mine[report.id] = res['editKey'] as String;
    await _saveMine();
    await saveContact(draft.contactName, draft.contactPhone);
    return report;
  }

  /// "resolve" (it turned up), "reopen" or "delete".
  Future<void> act(int id, String action) async {
    await _api.post('reports/action.php', {
      'id': id,
      'action': action,
      'editKey': _mine[id],
    });
    if (action == 'delete') {
      _mine.remove(id);
      await _saveMine();
    } else {
      notifyListeners();
    }
  }

  Future<void> flag(int id) =>
      _api.post('reports/action.php', {'id': id, 'action': 'flag'});

  /// The contact used last time, to fill in the next notice.
  Future<(String, String)> lastContact() async {
    final prefs = await SharedPreferences.getInstance();
    final parts = (prefs.getString(_contactKey) ?? '|').split('|');
    return (parts.first, parts.length > 1 ? parts[1] : '');
  }

  Future<void> saveContact(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactKey, '${name.replaceAll('|', ' ')}|$phone');
  }
}
