import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/lost_report.dart';
import '../services/lost_pets_service.dart';
import '../theme.dart';
import 'lost_report_form_screen.dart';

/// "Perdidas": the lost & found notices of the area, from sixsevenweb.com.
class LostPetsScreen extends StatefulWidget {
  const LostPetsScreen({super.key, this.service});

  final LostPetsService? service;

  @override
  State<LostPetsScreen> createState() => _LostPetsScreenState();
}

class _LostPetsScreenState extends State<LostPetsScreen> {
  late final _service = widget.service ?? LostPetsService.instance;
  ReportKind? _kind;
  late Future<List<LostReport>> _reports = _service.list();

  void _reload() => setState(() => _reports = _service.list(kind: _kind));

  Future<void> _publish() async {
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LostReportFormScreen()),
    );
    if (published == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perdidas y encontradas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_pin_outlined),
            tooltip: 'Mis avisos',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MyReportsScreen(service: _service),
                ),
              );
              _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _publish,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Publicar aviso'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<ReportKind?>(
              segments: const [
                ButtonSegment(value: null, label: Text('Todas')),
                ButtonSegment(value: ReportKind.lost, label: Text('Perdidas')),
                ButtonSegment(
                  value: ReportKind.found,
                  label: Text('Encontradas'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _kind = s.first;
                _reload();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _reports;
              },
              child: FutureBuilder<List<LostReport>>(
                future: _reports,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _Message(
                      text: '${snap.error}',
                      action: TextButton(
                        onPressed: _reload,
                        child: const Text('Reintentar'),
                      ),
                    );
                  }
                  final reports = snap.data!;
                  if (reports.isEmpty) {
                    return const _Message(
                      text: 'No hay avisos por ahora. Si se perdió tu mascota '
                          'o encontraste una, publicá un aviso.',
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      96 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    itemCount: reports.length,
                    itemBuilder: (_, i) => ReportCard(
                      report: reports[i],
                      service: _service,
                      onChanged: _reload,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh works on it too.
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(text, textAlign: TextAlign.center),
        if (action != null) Center(child: action),
      ],
    );
  }
}

/// One notice: its photos, what and where, and the button to write to
/// whoever published it.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.report,
    required this.service,
    this.onChanged,
  });

  final LostReport report;
  final LostPetsService service;
  final VoidCallback? onChanged;

  Future<void> _act(BuildContext context, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    if (action == 'delete' || action == 'flag') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'delete' ? '¿Borrar el aviso?' : '¿Denunciar el aviso?'),
          content: Text(action == 'delete'
              ? 'Deja de verse en la app y en la web.'
              : 'Si es falso, ofensivo o no es de una mascota, avisanos. '
                  'Con varias denuncias se oculta.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action == 'delete' ? 'Borrar' : 'Denunciar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      if (action == 'flag') {
        await service.flag(report.id);
      } else {
        await service.act(report.id, action);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(switch (action) {
          'resolve' => '¡Qué bueno! El aviso ya no se muestra.',
          'reopen' => 'El aviso se muestra de nuevo.',
          'delete' => 'Aviso borrado.',
          _ => 'Gracias, lo vamos a revisar.',
        }),
      ));
      onChanged?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lost = report.kind == ReportKind.lost;
    final mine = service.isMine(report.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.photos.isNotEmpty) _Photos(urls: report.photos),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Badge(
                      text: report.resolved
                          ? (lost ? 'Apareció' : 'Volvió a su casa')
                          : report.kind.badge,
                      color: report.resolved
                          ? Colors.grey
                          : lost
                              ? Brand.red
                              : Brand.teal,
                    ),
                    if (mine) ...[
                      const SizedBox(width: 6),
                      const _Badge(text: 'Tu aviso', color: Brand.orange),
                    ],
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: (a) => a == 'share'
                          ? SharePlus.instance.share(ShareParams(text: report.shareText()))
                          : _act(context, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'share', child: Text('Compartir')),
                        if (mine && !report.resolved)
                          PopupMenuItem(
                            value: 'resolve',
                            child: Text(lost ? '¡Ya apareció!' : 'Ya volvió a su casa'),
                          ),
                        if (mine && report.resolved)
                          const PopupMenuItem(value: 'reopen', child: Text('Mostrar de nuevo')),
                        if (mine)
                          const PopupMenuItem(value: 'delete', child: Text('Borrar aviso')),
                        if (!mine)
                          const PopupMenuItem(value: 'flag', child: Text('Denunciar')),
                      ],
                    ),
                  ],
                ),
                Text(report.title, style: theme.textTheme.titleLarge),
                if (report.details.isNotEmpty) Text(report.details),
                const SizedBox(height: 4),
                _Line(icon: Icons.schedule, text: report.whenLabel()),
                _Line(icon: Icons.place_outlined, text: report.zone),
                if (report.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Text(report.description),
                  ),
                const SizedBox(height: 8),
                if (!mine)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(report.contactName.isEmpty
                        ? 'WhatsApp'
                        : 'WhatsApp a ${report.contactName}'),
                    onPressed: () => launchUrl(
                      report.whatsAppUri(),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                else if (!report.resolved)
                  FilledButton.icon(
                    icon: const Icon(Icons.celebration_outlined),
                    label: Text(lost ? '¡Ya apareció!' : 'Ya volvió a su casa'),
                    onPressed: () => _act(context, 'resolve'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// The notice's photos, swiped sideways; tapping one opens it full screen.
class _Photos extends StatefulWidget {
  const _Photos({required this.urls});

  final List<String> urls;

  @override
  State<_Photos> createState() => _PhotosState();
}

class _PhotosState extends State<_Photos> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(backgroundColor: Colors.black),
                    body: InteractiveViewer(
                      child: Center(child: Image.network(widget.urls[i])),
                    ),
                  ),
                ),
              ),
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => Container(
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.pets, size: 48, color: Colors.white),
                ),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(color: Colors.grey.shade200),
              ),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.urls.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The notices published from this phone, to mark them solved or delete
/// them.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, required this.service});

  final LostPetsService service;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<LostReport>> _reports = widget.service.mine();

  void _reload() => setState(() => _reports = widget.service.mine());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis avisos')),
      body: FutureBuilder<List<LostReport>>(
        future: _reports,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return _Message(text: '${snap.error}');
          final reports = snap.data!;
          if (reports.isEmpty) {
            return const _Message(text: 'Todavía no publicaste avisos desde este celular.');
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final r in reports)
                ReportCard(report: r, service: widget.service, onChanged: _reload),
            ],
          );
        },
      ),
    );
  }
}
