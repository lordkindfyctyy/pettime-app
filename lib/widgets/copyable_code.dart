import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A family or caregiver code that is copied with one tap, ready to paste in
/// WhatsApp. The confirmation shows on the code itself, since a snackbar
/// would be hidden behind the bottom sheet it is in.
class CopyableCode extends StatefulWidget {
  const CopyableCode({super.key, required this.code, this.large = true});

  final String code;

  /// Big for the family code; smaller inside a caregiver's row.
  final bool large;

  @override
  State<CopyableCode> createState() => _CopyableCodeState();
}

class _CopyableCodeState extends State<CopyableCode> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeStyle =
        (widget.large ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)
            ?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: widget.large ? 4 : 2,
              color: Brand.red,
            );
    return Semantics(
      button: true,
      label: 'Copiar el código ${widget.code}',
      child: Material(
        color: Brand.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.code, style: codeStyle),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _copied ? Icons.check : Icons.copy,
                      size: 18,
                      color: _copied ? Brand.teal : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _copied
                            ? '¡Copiado! Ya lo podés pegar'
                            : 'Tocá para copiar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _copied ? Brand.teal : null,
                          fontWeight: _copied ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
