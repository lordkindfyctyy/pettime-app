import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import 'pettime_api.dart';

/// A pet's collar tag: its QR opens a page on sixsevenweb.com with the pet's
/// photo and the family's WhatsApp, so whoever finds it can let them know
/// without installing anything.
class PetTag {
  const PetTag({
    required this.code,
    required this.ownerKey,
    required this.url,
    required this.contactName,
    required this.contactPhone,
    required this.message,
    required this.lost,
  });

  /// The tag's code on the server (what the QR's link ends with).
  final String code;

  /// Edits or deletes the tag; the server only keeps its hash.
  final String ownerKey;

  /// The page the QR opens.
  final String url;
  final String contactName;
  final String contactPhone;

  /// What the family wants the finder to know (medicines, …).
  final String message;

  /// Marked as lost: the page says so in big letters.
  final bool lost;

  factory PetTag.fromJson(Map<String, dynamic> json) => PetTag(
        code: json['code'] as String,
        ownerKey: json['ownerKey'] as String,
        url: json['url'] as String,
        contactName: json['contactName'] as String? ?? '',
        contactPhone: json['contactPhone'] as String? ?? '',
        message: json['message'] as String? ?? '',
        lost: json['lost'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'ownerKey': ownerKey,
        'url': url,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'message': message,
        'lost': lost,
      };
}

/// The tags of this phone's pets, by pet id. Kept on the phone (like the
/// lost & found notices published from it): the key that edits a tag never
/// leaves it.
class TagService extends ChangeNotifier {
  TagService({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = TagService();
  static const _key = 'pet_tags_v1';
  static const _pendingKey = 'pet_tags_to_delete_v1';

  final PetTimeApi _api;
  Map<String, PetTag> _tags = {};

  /// Tags of pets that were deleted, still to be turned off on the server (it
  /// was not reachable, or the app closed before). They keep their key, which
  /// is what turns a public page off.
  List<PetTag> _pending = [];
  bool _retrying = false;

  PetTag? of(String petId) => _tags[petId];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _tags = {
          for (final MapEntry(:key, :value)
              in (jsonDecode(raw) as Map<String, dynamic>).entries)
            key: PetTag.fromJson(value as Map<String, dynamic>),
        };
      } catch (e) {
        debugPrint('Could not read the tags: $e');
      }
    }
    final pending = prefs.getString(_pendingKey);
    if (pending != null) {
      try {
        _pending = [
          for (final t in jsonDecode(pending) as List)
            PetTag.fromJson(t as Map<String, dynamic>),
        ];
      } catch (e) {
        debugPrint('Could not read the tags to delete: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in _tags.entries) e.key: e.value.toJson()}),
    );
    await prefs.setString(
      _pendingKey,
      jsonEncode([for (final t in _pending) t.toJson()]),
    );
    notifyListeners();
  }

  /// The pet was deleted: its tag goes with it, so its public page (name,
  /// photo and the family's WhatsApp) doesn't stay online with nobody able to
  /// turn it off. If the server can't be reached now, it is retried on the
  /// next start.
  Future<void> removeForPet(String petId) async {
    final tag = _tags.remove(petId);
    if (tag == null) return;
    _pending.add(tag);
    await _persist();
    await retryPending();
  }

  /// Turns off on the server the tags of deleted pets that are still online.
  Future<void> retryPending() async {
    if (_retrying || _pending.isEmpty) return;
    _retrying = true;
    try {
      for (final tag in List.of(_pending)) {
        try {
          await _api.post('tags/delete.php', {
            'code': tag.code,
            'ownerKey': tag.ownerKey,
          });
        } on ApiException catch (e) {
          // Already gone from the server; any other error is tried again later.
          if (!e.isNotFound) {
            debugPrint('Could not turn off the tag ${tag.code}: $e');
            continue;
          }
        }
        _pending.remove(tag);
      }
      await _persist();
    } finally {
      _retrying = false;
    }
  }

  /// Creates the pet's tag, or updates it (name, photo, contact, lost…).
  Future<PetTag> save(
    Pet pet, {
    required String contactName,
    required String contactPhone,
    String message = '',
    bool lost = false,
  }) async {
    final old = _tags[pet.id];
    final photo = pet.photoPath == null ? null : File(pet.photoPath!);
    final res = await _api.upload(
      'tags/save.php',
      fields: {
        'petName': pet.name,
        'species': pet.species,
        'contactName': contactName.trim(),
        'contactPhone': contactPhone.trim(),
        'message': message.trim(),
        'lost': lost ? '1' : '0',
        if (old != null) 'code': old.code,
        if (old != null) 'ownerKey': old.ownerKey,
        if (photo == null || !photo.existsSync()) 'removePhoto': '1',
      },
      files: {
        if (photo != null && photo.existsSync()) 'photo': [photo],
      },
    );
    final t = res['tag'] as Map<String, dynamic>;
    final tag = PetTag(
      code: t['code'] as String,
      ownerKey: res['ownerKey'] as String? ?? old!.ownerKey,
      url: t['url'] as String,
      contactName: t['contactName'] as String? ?? '',
      contactPhone: t['contactPhone'] as String? ?? '',
      message: t['message'] as String? ?? '',
      lost: t['lost'] as bool? ?? false,
    );
    _tags[pet.id] = tag;
    await _persist();
    return tag;
  }

  /// Marks the pet as lost or found again on its tag's page.
  Future<PetTag> setLost(Pet pet, bool lost) {
    final tag = _tags[pet.id]!;
    return save(
      pet,
      contactName: tag.contactName,
      contactPhone: tag.contactPhone,
      message: tag.message,
      lost: lost,
    );
  }

  /// Turns the tag off: its QR no longer shows the pet.
  Future<void> delete(String petId) async {
    final tag = _tags[petId];
    if (tag == null) return;
    try {
      await _api.post('tags/delete.php', {
        'code': tag.code,
        'ownerKey': tag.ownerKey,
      });
    } on ApiException catch (e) {
      // Already gone from the server: only this phone still had it.
      if (!e.isNotFound) rethrow;
    }
    _tags.remove(petId);
    await _persist();
  }
}
