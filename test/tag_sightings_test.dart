import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/services/tag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake tags API: saves one tag and answers its sightings.
class FakeServer {
  List<Map<String, dynamic>> sightings = [];
  String? askedKey;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('tags/save.php')) {
      return http.Response(
        jsonEncode({
          'ok': true,
          'tag': {
            'code': 'K7Q2M9XP',
            'contactPhone': '5491164722908',
            'lost': true,
            'url': 'https://sixsevenweb.com/pettime/chapita.php?c=K7Q2M9XP',
          },
          'ownerKey': 'k3y',
        }),
        200,
      );
    }
    if (path.endsWith('tags/sightings.php')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      askedKey = body['ownerKey'] as String?;
      return http.Response(
        jsonEncode({'ok': true, 'sightings': sightings}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('', 404);
  });
}

Map<String, dynamic> sighting(int id, String at, {String address = 'Belgrano 1042, San Fernando'}) => {
  'id': id,
  'lat': -34.4425,
  'lng': -58.559,
  'accuracy': 20,
  'address': address,
  'mapsUrl': 'https://www.google.com/maps/search/?api=1&query=-34.442500%2C-58.559000',
  'at': at,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses a sighting and falls back to the coordinates', () {
    final s = TagSighting.fromJson(sighting(3, '2026-11-23T01:54:08Z', address: ''));
    expect(s.id, 3);
    expect(s.accuracy, 20);
    expect(s.at.toUtc(), DateTime.utc(2026, 11, 23, 1, 54, 8));
    expect(s.label, '-34.44250, -58.55900');
    expect(TagSighting.fromJson(sighting(4, '2026-11-23T01:54:08Z')).label, 'Belgrano 1042, San Fernando');
  });

  test('tells about new sightings only once, with the tag key', () async {
    final server = FakeServer();
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await tags.load();
    await tags.save(Pet(id: 'p1', name: 'Pancho', species: 'Perro'), contactName: 'Lalo', contactPhone: '1164722908', lost: true);
    final now = DateTime.utc(2026, 11, 23, 2);

    // First look: an old sighting is not news; it only marks where we are.
    server.sightings = [sighting(1, '2026-11-01T10:00:00Z')];
    expect(await tags.checkNewSightings(now: now), isEmpty);
    expect(server.askedKey, 'k3y');

    // A new one arrives: one notice, with the pet id.
    server.sightings = [sighting(2, '2026-11-23T01:54:08Z'), sighting(1, '2026-11-01T10:00:00Z')];
    final found = await tags.checkNewSightings(now: now);
    expect(found.length, 1);
    expect(found.first.$1, 'p1');
    expect(found.first.$2.id, 2);
    expect(tags.sightingsOf('p1').length, 2);

    // Nothing new: no notice again, even after the app restarts.
    final again = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await again.load();
    expect(await again.checkNewSightings(now: now), isEmpty);
  });

  test('a recent sighting is news the first time this phone looks', () async {
    final server = FakeServer();
    final tags = TagService(api: PetTimeApi(client: server.client, base: 'https://x'));
    await tags.save(Pet(id: 'p1', name: 'Pancho', species: 'Perro'), contactName: 'Lalo', contactPhone: '1164722908');
    server.sightings = [sighting(5, '2026-11-23T01:30:00Z')];
    final found = await tags.checkNewSightings(now: DateTime.utc(2026, 11, 23, 2));
    expect(found.map((e) => e.$2.id), [5]);
  });
}
