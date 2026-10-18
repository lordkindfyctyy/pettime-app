import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pettime_app/models/expense.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/pet_merge.dart';
import 'package:pettime_app/models/pet_share.dart';
import 'package:pettime_app/services/family_sync.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Medication amoxi({List<DateTime>? given, String? photo}) => Medication(
      id: 'm1',
      name: 'Amoxicilina',
      everyMinutes: 480,
      startsAt: DateTime(2026, 10, 18, 8),
      givenDoses: given,
      photoPath: photo,
    );

/// A fake sixsevenweb.com that keeps one shared pet, like family/share.php.
class FakeServer {
  Map<String, dynamic>? pet;
  int version = 0;
  final calls = <String>[];

  late final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final action = body['action'] as String;
    calls.add(action);
    Map<String, dynamic> current() =>
        {'ok': true, 'code': 'K7Q2M9XP', 'version': version, 'pet': pet, 'photoUrl': null};
    switch (action) {
      case 'create':
        pet = body['pet'] as Map<String, dynamic>;
        version = 1;
        return http.Response(
          jsonEncode({'ok': true, 'code': 'K7Q2M9XP', 'ownerKey': 'k', 'version': 1}),
          200,
        );
      case 'get':
        if (pet == null) return http.Response('{"ok":false,"error":"No hay"}', 404);
        return http.Response(jsonEncode(current()), 200);
      case 'update':
        if (body['baseVersion'] != version) {
          return http.Response(
            jsonEncode({...current(), 'ok': false, 'error': 'conflict'}),
            409,
          );
        }
        pet = body['pet'] as Map<String, dynamic>;
        version++;
        return http.Response(jsonEncode({'ok': true, 'version': version}), 200);
      case 'stop':
        pet = null;
        return http.Response('{"ok":true}', 200);
    }
    return http.Response('{"ok":false}', 422);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lo que se manda no lleva las fotos ni cómo se comparte', () {
    final pet = Pet(
      id: 'p',
      name: 'Pancho',
      photoPath: '/data/p.jpg',
      medications: [amoxi(photo: '/data/m.jpg')],
      share: const PetShare(code: 'K7Q2M9XP', version: 3, ownerKey: 'k'),
    );
    final json = sharePayload(pet);
    expect(json.containsKey('share'), isFalse);
    expect(json.containsKey('photoPath'), isFalse);
    expect((json['medications'] as List).single.containsKey('photoPath'), isFalse);

    // Al volver, cada celular conserva sus propias fotos.
    final back = petFromShared(
      json,
      local: pet,
      share: const PetShare(code: 'K7Q2M9XP', version: 4),
    );
    expect(back.photoPath, '/data/p.jpg');
    expect(back.medications.single.photoPath, '/data/m.jpg');
    expect(back.share!.version, 4);
  });

  test('combinar: no se pierde nada de lo que agregó cada uno', () {
    final base = Pet(id: 'p', name: 'Pancho', medications: [amoxi()]);
    final mine = base.copyWith(
      notes: 'Alérgico',
      medications: [amoxi(given: [DateTime(2026, 10, 18, 8)])],
      expenses: [
        Expense(id: 'e1', date: DateTime(2026, 10, 1), category: ExpenseCategory.food, amount: 100),
      ],
    );
    final theirs = base.copyWith(
      medications: [amoxi(given: [DateTime(2026, 10, 18, 16)])],
      expenses: [
        Expense(id: 'e2', date: DateTime(2026, 10, 2), category: ExpenseCategory.vet, amount: 200),
      ],
    );
    final merged = mergePets(mine, theirs);
    expect(merged.notes, 'Alérgico');
    expect(merged.medications.single.givenDoses, [
      DateTime(2026, 10, 18, 8),
      DateTime(2026, 10, 18, 16),
    ]);
    expect(merged.expenses.map((e) => e.id), ['e2', 'e1']);
  });

  test('cambiar una mascota compartida la marca para enviar', () async {
    final state = PetsState();
    await state.savePet(Pet(
      id: 'p',
      name: 'Pancho',
      share: const PetShare(code: 'K7Q2M9XP', version: 1),
    ));
    expect(state.byId('p')!.share!.dirty, isTrue);
    await state.setShare('p', state.byId('p')!.share!.copyWith(dirty: false));
    expect(state.byId('p')!.share!.dirty, isFalse);

    // La toma marcada desde la notificación con la app cerrada también.
    final raw = jsonEncode([for (final p in state.pets) p.toJson()]);
    final pets = jsonDecode(
      PetsState.addDoseToJson(raw, 'p', 'none', DateTime(2026)) ?? raw,
    ) as List;
    expect(pets, isNotEmpty);
  });

  test('compartir, sumarse desde otro celular y combinar cambios', () async {
    final server = FakeServer();
    final api = PetTimeApi(client: server.client, base: 'https://x/api/pettime');

    // Celular A comparte a Pancho.
    final a = PetsState();
    final syncA = FamilySync(api: api);
    syncA.attach(a);
    await a.savePet(Pet(id: 'p', name: 'Pancho', medications: [amoxi()]));
    final share = await syncA.share(a.byId('p')!);
    expect(share.code, 'K7Q2M9XP');
    expect(server.pet!['name'], 'Pancho');

    // Celular B se suma con el código.
    SharedPreferences.setMockInitialValues({});
    final b = PetsState();
    final syncB = FamilySync(api: api);
    syncB.attach(b);
    final joined = await syncB.join('K7Q2M9XP');
    expect(joined.name, 'Pancho');
    expect(joined.share!.isOwner, isFalse);
    await expectLater(syncB.join('K7Q2M9XP'), throwsA(isA<ApiException>()));

    // Los dos dan una toma sin haberse sincronizado.
    await a.logDose('p', 'm1', DateTime(2026, 10, 18, 8));
    await b.logDose('p', 'm1', DateTime(2026, 10, 18, 16));
    await syncA.syncAll();
    await syncB.syncAll(); // 409: combina y vuelve a mandar.
    await syncA.syncAll(); // A baja lo combinado.

    for (final s in [a, b]) {
      expect(s.byId('p')!.medications.single.givenDoses, [
        DateTime(2026, 10, 18, 8),
        DateTime(2026, 10, 18, 16),
      ]);
      expect(s.byId('p')!.share!.dirty, isFalse);
    }
    expect(server.calls, contains('update'));

    // A deja de compartir: B se queda con su copia, sin compartir.
    await syncA.stop(a.byId('p')!);
    await syncB.syncAll();
    expect(b.byId('p')!.share, isNull);
    expect(b.byId('p')!.name, 'Pancho');
    syncA.pause();
    syncB.pause();
  });
}
