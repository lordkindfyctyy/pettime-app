import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// PetTime's server on sixsevenweb.com (public/pettime/api in the website
/// repo): lost & found pets, the shop catalog and pets shared with the
/// family. To try a local server:
///   flutter run --dart-define=PETTIME_API=http://localhost:8000/pettime/api
const pettimeApiBase = String.fromEnvironment(
  'PETTIME_API',
  defaultValue: 'https://sixsevenweb.com/pettime/api',
);

/// A failed request, with the message to show (already in Spanish).
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.body});

  final String message;
  final int status;

  /// The decoded response, e.g. the current pet on a 409 conflict.
  final Map<String, dynamic>? body;

  bool get isConflict => status == 409;
  bool get isNotFound => status == 404;

  @override
  String toString() => message;
}

class PetTimeApi {
  PetTimeApi({http.Client? client, this.base = pettimeApiBase})
      : _client = client ?? http.Client();

  static final instance = PetTimeApi();

  final http.Client _client;
  final String base;

  static const _timeout = Duration(seconds: 25);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$base/$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? query,
  ]) =>
      _send(() => _client.get(_uri(path, query)).timeout(_timeout));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send(() => _client
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout));

  /// Multipart POST: [files] maps each field name ("photos[]", "photo") to
  /// the files to send in it.
  Future<Map<String, dynamic>> upload(
    String path, {
    Map<String, String> fields = const {},
    Map<String, List<File>> files = const {},
  }) =>
      _send(() async {
        final request = http.MultipartRequest('POST', _uri(path))
          ..fields.addAll(fields);
        for (final MapEntry(key: field, value: list) in files.entries) {
          for (final f in list) {
            request.files.add(await http.MultipartFile.fromPath(field, f.path));
          }
        }
        final streamed =
            await _client.send(request).timeout(const Duration(minutes: 2));
        return http.Response.fromStream(streamed);
      });

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request();
    } on SocketException {
      throw ApiException('No hay conexión a internet.');
    } on http.ClientException {
      throw ApiException('No hay conexión a internet.');
    } on Exception {
      throw ApiException('El servidor no responde. Probá de nuevo en un rato.');
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body?['ok'] == true) {
      return body!;
    }
    final error = body?['error'];
    throw ApiException(
      error is String && error != 'conflict'
          ? error
          : response.statusCode == 429
              ? 'Demasiados intentos. Probá de nuevo en un rato.'
              : 'Algo salió mal en el servidor. Probá de nuevo en un rato.',
      status: response.statusCode,
      body: body,
    );
  }

  /// Downloads [url] into [target].
  Future<File> download(String url, File target) async {
    final response = await _client.get(Uri.parse(url)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw ApiException('No se pudo bajar la foto.', status: response.statusCode);
    }
    await target.parent.create(recursive: true);
    return target.writeAsBytes(response.bodyBytes);
  }
}
