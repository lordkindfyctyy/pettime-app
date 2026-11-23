import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_lang.dart';
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
    this.food = '',
    this.conditions = '',
    this.medications = '',
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

  /// Shown on the page under "what you should know about me": what it eats,
  /// health conditions and medications (also what an NFC tag on the collar opens).
  final String food;
  final String conditions;
  final String medications;

  /// Marked as lost: the page says so in big letters.
  final bool lost;

  factory PetTag.fromJson(Map<String, dynamic> json) => PetTag(
    code: json['code'] as String,
    ownerKey: json['ownerKey'] as String,
    url: json['url'] as String,
    contactName: json['contactName'] as String? ?? '',
    contactPhone: json['contactPhone'] as String? ?? '',
    message: json['message'] as String? ?? '',
    food: json['food'] as String? ?? '',
    conditions: json['conditions'] as String? ?? '',
    medications: json['medications'] as String? ?? '',
    lost: json['lost'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'ownerKey': ownerKey,
    'url': url,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'message': message,
    'food': food,
    'conditions': conditions,
    'medications': medications,
    'lost': lost,
  };
}

/// Where someone who scanned the tag (QR or NFC) said the pet is: their
/// browser asked them and they agreed to share their location.
class TagSighting {
  const TagSighting({
    required this.id,
    required this.lat,
    required this.lng,
    required this.address,
    required this.mapsUrl,
    required this.at,
    this.accuracy,
  });

  final int id;
  final double lat;
  final double lng;

  /// Meters; null if the browser didn't say.
  final int? accuracy;

  /// Approximate street address (OpenStreetMap); may be empty.
  final String address;

  /// Google Maps on that point.
  final String mapsUrl;
  final DateTime at;

  /// The address, or the coordinates when there is none.
  String get label => address.isNotEmpty
      ? address
      : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  factory TagSighting.fromJson(Map<String, dynamic> json) => TagSighting(
    id: (json['id'] as num).toInt(),
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toInt(),
    address: json['address'] as String? ?? '',
    mapsUrl: json['mapsUrl'] as String,
    at: DateTime.parse(json['at'] as String).toLocal(),
  );
}

/// The tags of this phone's pets, by pet id. Kept on the phone (like the
/// lost & found notices published from it): the key that edits a tag never
/// leaves it.
class TagService extends ChangeNotifier {
  TagService({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = TagService();
  static const _key = 'pet_tags_v1';
  static const _pendingKey = 'pet_tags_to_delete_v1';
  static const _seenKey = 'tag_sightings_seen_v1';

  /// A sighting this recent still deserves a notice the first time this phone
  /// looks (e.g. right after updating the app).
  static const freshSighting = Duration(hours: 24);

  final PetTimeApi _api;
  Map<String, PetTag> _tags = {};

  /// The last sightings fetched, by pet id (newest first).
  final Map<String, List<TagSighting>> _sightings = {};

  /// The newest sighting id this phone already told the family about, by pet id.
  Map<String, int>? _seen;
  Timer? _watch;
  void Function(String petId, TagSighting sighting)? _onNewSighting;

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
    String food = '',
    String conditions = '',
    String medications = '',
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
        'food': food.trim(),
        'conditions': conditions.trim(),
        'medications': medications.trim(),
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
    // A new tag always comes with its key; without it this phone could never
    // edit or turn the page off.
    final ownerKey = res['ownerKey'] as String? ?? old?.ownerKey;
    if (ownerKey == null) {
      throw ApiException(
        tr('El servidor no devolvió la clave de la chapita. Probá de nuevo.'),
      );
    }
    final tag = PetTag(
      code: t['code'] as String,
      ownerKey: ownerKey,
      url: t['url'] as String,
      contactName: t['contactName'] as String? ?? '',
      contactPhone: t['contactPhone'] as String? ?? '',
      message: t['message'] as String? ?? '',
      // An older server doesn't send them back: keep what was typed
      food: t['food'] as String? ?? food.trim(),
      conditions: t['conditions'] as String? ?? conditions.trim(),
      medications: t['medications'] as String? ?? medications.trim(),
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
      food: tag.food,
      conditions: tag.conditions,
      medications: tag.medications,
      lost: lost,
    );
  }

  /// The last sightings already fetched for the pet (newest first).
  List<TagSighting> sightingsOf(String petId) => _sightings[petId] ?? const [];

  /// Where people who scanned the pet's tag said it is (newest first).
  Future<List<TagSighting>> fetchSightings(String petId) async {
    final tag = _tags[petId];
    if (tag == null) return const [];
    final res = await _api.post('tags/sightings.php', {
      'code': tag.code,
      'ownerKey': tag.ownerKey,
    });
    final list = [
      for (final s in res['sightings'] as List? ?? const [])
        TagSighting.fromJson(s as Map<String, dynamic>),
    ];
    _sightings[petId] = list;
    notifyListeners();
    return list;
  }

  /// Looks for sightings this phone hasn't told the family about yet. The
  /// first time a tag is checked, only one from the last [freshSighting] counts
  /// (old ones would be noise). An unreachable server is tried next time.
  Future<List<(String, TagSighting)>> checkNewSightings({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = _seen ??= {
      for (final MapEntry(:key, :value)
          in (jsonDecode(prefs.getString(_seenKey) ?? '{}') as Map<String, dynamic>)
              .entries)
        key: (value as num).toInt(),
    };
    final clock = now ?? DateTime.now();
    final found = <(String, TagSighting)>[];
    for (final petId in _tags.keys.toList()) {
      List<TagSighting> list;
      try {
        list = await fetchSightings(petId);
      } catch (e) {
        debugPrint('Could not check the sightings of $petId: $e');
        continue;
      }
      final last = seen[petId];
      final fresh = last == null
          ? list.take(1).where((s) => clock.difference(s.at) < freshSighting)
          : list.where((s) => s.id > last);
      found.addAll([for (final s in fresh) (petId, s)]);
      if (list.isNotEmpty) seen[petId] = list.first.id;
      if (last == null && list.isEmpty) seen[petId] = 0;
    }
    seen.removeWhere((petId, _) => !_tags.containsKey(petId));
    await prefs.setString(_seenKey, jsonEncode(seen));
    return found;
  }

  /// While the app is open: look for new sightings now and every few minutes,
  /// and tell [onNew] about each one.
  void startWatching(void Function(String petId, TagSighting sighting) onNew) {
    _onNewSighting = onNew;
    resumeWatching();
  }

  void resumeWatching() {
    if (_onNewSighting == null) return;
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(minutes: 3), (_) => _check());
    unawaited(_check());
  }

  void pauseWatching() {
    _watch?.cancel();
    _watch = null;
  }

  Future<void> _check() async {
    final onNew = _onNewSighting;
    if (onNew == null || _tags.isEmpty) return;
    for (final (petId, s) in await checkNewSightings()) {
      onNew(petId, s);
    }
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
