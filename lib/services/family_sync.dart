import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pet.dart';
import '../models/pet_merge.dart';
import '../models/pet_share.dart';
import '../state/pets_state.dart';
import 'pettime_api.dart';
import 'photo_service.dart';

/// Pets shared with the family: every phone that joined with the code sees
/// and changes the same pet through sixsevenweb.com.
///
/// Each phone keeps its own copy (it all works offline) and syncs it: right
/// after a change, when the app opens or comes back, and every minute while
/// it is open. If two phones changed the pet at the same time, the server
/// answers 409 and the changes are combined (see [mergePets]).
class FamilySync {
  FamilySync({PetTimeApi? api}) : _api = api ?? PetTimeApi.instance;

  static final instance = FamilySync();

  final PetTimeApi _api;
  PetsState? _state;
  Timer? _debounce;
  Timer? _periodic;
  final _pending = <String>{};
  Future<void>? _running;

  /// Starts syncing [state]'s shared pets. Until this is called (as in
  /// tests) changes are only marked to be sent.
  void attach(PetsState state) {
    _state = state;
    resume();
  }

  /// The app is in the foreground: sync now and every minute.
  void resume() {
    if (_state == null) return;
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) => syncAll());
    unawaited(syncAll());
  }

  /// The app went to the background.
  void pause() {
    _periodic?.cancel();
    _periodic = null;
  }

  /// A shared pet changed here: send it in a moment (several quick changes
  /// go together).
  void schedule(String petId) {
    if (_state == null) return;
    _pending.add(petId);
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      final ids = {..._pending};
      _pending.clear();
      unawaited(_run(() async {
        for (final id in ids) {
          await _syncPet(id);
        }
      }));
    });
  }

  Future<void> syncAll() => _run(() async {
        final state = _state;
        if (state == null) return;
        for (final pet in state.pets.where((p) => p.share != null).toList()) {
          await _syncPet(pet.id);
        }
      });

  /// One sync at a time, so two can't send the same change twice.
  Future<void> _run(Future<void> Function() task) async {
    while (_running != null) {
      await _running;
    }
    final future = () async {
      try {
        await task();
      } catch (e) {
        debugPrint('Family sync failed: $e');
      }
    }();
    _running = future;
    await future;
    _running = null;
  }

  Future<void> _syncPet(String petId) async {
    final state = _state!;
    for (var attempt = 0; attempt < 3; attempt++) {
      final pet = state.byId(petId);
      final share = pet?.share;
      if (pet == null || share == null) return;
      try {
        if (share.dirty) {
          final res = await _api.post('family/share.php', {
            'action': 'update',
            'code': share.code,
            'baseVersion': share.version,
            'pet': sharePayload(pet),
          });
          // Only if nothing changed here while it was being sent.
          final now = state.byId(petId);
          if (now != null && identical(now, pet)) {
            await state.setShare(
              petId,
              share.copyWith(version: res['version'] as int, dirty: false),
            );
          }
        } else {
          final res = await _api.post('family/share.php', {
            'action': 'get',
            'code': share.code,
          });
          if ((res['version'] as int) > share.version) {
            await _applyRemote(pet, res);
          }
        }
        await _uploadPhotoIfNeeded(petId);
        return;
      } on ApiException catch (e) {
        if (e.isConflict && e.body != null) {
          // Someone else saved first: combine and send again.
          final remote = petFromShared(
            e.body!['pet'] as Map<String, dynamic>,
            local: pet,
            share: share,
          );
          final merged = mergePets(pet, remote).copyWith(
            share: share.copyWith(version: e.body!['version'] as int, dirty: true),
          );
          await state.applySharedPet(merged);
          await _downloadPhotoIfNew(petId, e.body!['photoUrl'] as String?);
          continue;
        }
        if (e.isNotFound) {
          // They stopped sharing it: it stays on this phone as its own.
          await state.setShare(petId, null);
        }
        return;
      }
    }
  }

  Future<void> _applyRemote(Pet local, Map<String, dynamic> res) async {
    final share = local.share!.copyWith(version: res['version'] as int);
    final pet = petFromShared(
      res['pet'] as Map<String, dynamic>,
      local: local,
      share: share,
    );
    await _state!.applySharedPet(pet);
    await _downloadPhotoIfNew(local.id, res['photoUrl'] as String?);
  }

  Future<void> _downloadPhotoIfNew(String petId, String? url) async {
    final state = _state!;
    final pet = state.byId(petId);
    if (pet == null || url == null || url == pet.share?.photoUrl) return;
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/pet_photos',
    );
    final file = await _api.download(
      url,
      File('${dir.path}/${petId}_${DateTime.now().millisecondsSinceEpoch}.jpg'),
    );
    final now = state.byId(petId)!;
    await PhotoService.instance.delete(now.photoPath);
    await state.applySharedPet(now.copyWith(
      photoPath: file.path,
      share: now.share!.copyWith(photoUrl: url, uploadedPhotoPath: file.path),
    ));
  }

  Future<void> _uploadPhotoIfNeeded(String petId) async {
    final state = _state!;
    final pet = state.byId(petId);
    final share = pet?.share;
    final path = pet?.photoPath;
    if (share == null || path == null || path == share.uploadedPhotoPath) {
      return;
    }
    if (!await File(path).exists()) return;
    final res = await _api.upload(
      'family/photo.php',
      fields: {'code': share.code},
      files: {
        'photo': [File(path)],
      },
    );
    final now = state.byId(petId);
    if (now?.share == null) return;
    // The photo bumps the version; this phone already has it.
    await state.setShare(
      petId,
      now!.share!.copyWith(
        version: now.share!.dirty ? null : res['version'] as int,
        photoUrl: res['photoUrl'] as String,
        uploadedPhotoPath: path,
      ),
    );
  }

  /// Shares [pet]: returns its code for the family.
  Future<PetShare> share(Pet pet) async {
    final res = await _api.post('family/share.php', {
      'action': 'create',
      'pet': sharePayload(pet),
    });
    final share = PetShare(
      code: res['code'] as String,
      version: res['version'] as int,
      ownerKey: res['ownerKey'] as String,
    );
    await _state!.setShare(pet.id, share);
    unawaited(_run(() => _uploadPhotoIfNeeded(pet.id)));
    return share;
  }

  /// Joins the pet shared with [code]: it is added to this phone.
  Future<Pet> join(String code) async {
    final res = await _api.post('family/share.php', {
      'action': 'get',
      'code': code,
    });
    final remote = res['pet'] as Map<String, dynamic>;
    final existing = _state!.byId(remote['id'] as String);
    if (existing != null) {
      throw ApiException(existing.share != null
          ? '${existing.name} ya está compartida en este celular.'
          : '${existing.name} ya está en este celular: la compartiste desde acá.');
    }
    final pet = petFromShared(
      remote,
      share: PetShare(code: res['code'] as String, version: res['version'] as int),
    );
    await _state!.applySharedPet(pet);
    try {
      await _downloadPhotoIfNew(pet.id, res['photoUrl'] as String?);
    } catch (e) {
      debugPrint('Could not download the pet photo: $e');
    }
    return _state!.byId(pet.id)!;
  }

  /// Stops sharing [pet] (only the phone that shared it). The other phones
  /// keep their copy, no longer synced.
  Future<void> stop(Pet pet) async {
    final share = pet.share!;
    await _api.post('family/share.php', {
      'action': 'stop',
      'code': share.code,
      'ownerKey': share.ownerKey,
    });
    await _state!.setShare(pet.id, null);
  }

  /// This phone stops getting the family's changes; it keeps its copy.
  Future<void> leave(Pet pet) => _state!.setShare(pet.id, null);
}
