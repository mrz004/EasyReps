import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks a yes/no question. Returns true only when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size(64, 40),
                  )
                : FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Faint helper text, e.g. empty states.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key, this.textAlign = TextAlign.center});
  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Exercise image from the bundled assets, with a neutral fallback.
class ExerciseImage extends StatelessWidget {
  const ExerciseImage({
    super.key,
    required this.asset,
    this.size,
    this.cacheWidth,
    this.borderRadius = 8,
  });

  final String? asset;
  final double? size;
  final int? cacheWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.fitness_center, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: asset == null
          ? fallback
          : Image.asset(
              asset!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// Input formatters for numeric fields.
List<TextInputFormatter> get decimalInputFormatters => [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];
List<TextInputFormatter> get integerInputFormatters => [
  FilteringTextInputFormatter.digitsOnly,
];
const TextInputType DECIMAL_KEYBOARD = TextInputType.numberWithOptions(decimal: true);
