import 'package:flutter/services.dart';

import '../l10n/app_lang.dart';

/// Writes the collar tag's page link on an NFC sticker or tag: whoever finds the
/// pet touches it with their phone and the page opens, without PetTime. The
/// Android side is in MainActivity.kt (channel "pettime/nfc").
class NfcTagWriter {
  NfcTagWriter._();
  static final instance = NfcTagWriter._();
  static const _channel = MethodChannel('pettime/nfc');

  /// 'sin' (no NFC on this phone), 'apagado' (turned off) or 'listo'.
  Future<String> status() async {
    try {
      return await _channel.invokeMethod<String>('estado') ?? 'sin';
    } catch (_) {
      return 'sin';
    }
  }

  /// Waits up to 60 s for a sticker and writes [url]. Returns 'ok',
  /// 'cancelado' or a message to show.
  Future<String> write(String url) async {
    String code;
    try {
      code =
          await _channel.invokeMethod<String>('grabar', {'uri': url}) ??
          'error';
    } catch (_) {
      code = 'sin';
    }
    return switch (code) {
      'ok' || 'cancelado' => code,
      'sin' => tr('Este teléfono no tiene NFC.'),
      'apagado' => tr(
        'El NFC está apagado: prendelo en los ajustes del teléfono.',
      ),
      'tiempo' => tr('No se acercó ninguna placa. Probá de nuevo.'),
      'bloqueado' => tr('Esa placa está bloqueada y no se puede grabar.'),
      'chico' => tr('La placa es muy chica para el link.'),
      'noSirve' => tr('Esa placa no sirve para grabar (no es NFC NDEF).'),
      _ => tr(
        'No se pudo grabar. Dejá la placa quieta contra el celular y probá de nuevo.',
      ),
    };
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancelar');
    } catch (_) {}
  }
}
