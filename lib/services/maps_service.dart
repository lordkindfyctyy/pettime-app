import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_lang.dart';

/// Opens [uri] in Google Maps (or the browser when the app is not installed).
Future<void> openInMaps(BuildContext context, Uri? uri) async {
  final messenger = ScaffoldMessenger.of(context);
  if (uri == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Cargá el nombre o la dirección del lugar'))),
    );
    return;
  }
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('No se pudo abrir Google Maps'))),
    );
  }
}
