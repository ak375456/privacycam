import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

bool usesCupertinoUi(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

IconData adaptiveIcon(
  BuildContext context, {
  required IconData material,
  required IconData cupertino,
}) => usesCupertinoUi(context) ? cupertino : material;

PreferredSizeWidget adaptiveNavigationBar(
  BuildContext context, {
  required Widget title,
  List<Widget> actions = const [],
  Widget? leading,
  bool automaticallyImplyLeading = true,
}) {
  if (usesCupertinoUi(context)) {
    final resolvedLeading =
        leading ??
        (automaticallyImplyLeading && Navigator.canPop(context)
            ? CupertinoNavigationBarBackButton(
                onPressed: () => Navigator.maybePop(context),
              )
            : null);
    return CupertinoNavigationBar(
      middle: title,
      leading: resolvedLeading,
      automaticallyImplyLeading: false,
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
      backgroundColor: const Color(0xF2F7F8F5),
      border: const Border(
        bottom: BorderSide(color: Color(0x22000000), width: .5),
      ),
    );
  }
  return AppBar(
    title: title,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    actions: actions,
  );
}

class AdaptiveIconButton extends StatelessWidget {
  const AdaptiveIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (!usesCupertinoUi(context)) {
      return IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon);
    }
    final color = onPressed == null
        ? CupertinoColors.inactiveGray
        : CupertinoTheme.of(context).primaryColor;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          minimumSize: const Size(38, 44),
          onPressed: onPressed,
          child: IconTheme(
            data: IconThemeData(color: color, size: 22),
            child: icon,
          ),
        ),
      ),
    );
  }
}

enum AdaptiveButtonStyle { primary, secondary, plain }

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style = AdaptiveButtonStyle.primary,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final AdaptiveButtonStyle style;

  Widget get content => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (icon != null) ...[icon!, const SizedBox(width: 8)],
      child,
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (usesCupertinoUi(context)) {
      final button = switch (style) {
        AdaptiveButtonStyle.primary => CupertinoButton.filled(
          minimumSize: const Size(48, 52),
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          onPressed: onPressed,
          child: content,
        ),
        AdaptiveButtonStyle.secondary => CupertinoButton.tinted(
          minimumSize: const Size(48, 50),
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          onPressed: onPressed,
          child: content,
        ),
        AdaptiveButtonStyle.plain => CupertinoButton(
          minimumSize: const Size(40, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: onPressed,
          child: content,
        ),
      };
      return DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        child: button,
      );
    }
    if (icon == null) {
      return switch (style) {
        AdaptiveButtonStyle.primary => FilledButton(
          onPressed: onPressed,
          child: child,
        ),
        AdaptiveButtonStyle.secondary => OutlinedButton(
          onPressed: onPressed,
          child: child,
        ),
        AdaptiveButtonStyle.plain => TextButton(
          onPressed: onPressed,
          child: child,
        ),
      };
    }
    return switch (style) {
      AdaptiveButtonStyle.primary => FilledButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
      ),
      AdaptiveButtonStyle.secondary => OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
      ),
      AdaptiveButtonStyle.plain => TextButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
      ),
    };
  }
}

class AdaptiveProgressIndicator extends StatelessWidget {
  const AdaptiveProgressIndicator({super.key, this.color, this.dimension = 20});

  final Color? color;
  final double dimension;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: dimension,
    child: usesCupertinoUi(context)
        ? CupertinoActivityIndicator(color: color, radius: dimension / 2)
        : CircularProgressIndicator(color: color, strokeWidth: 2.5),
  );
}

class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => usesCupertinoUi(context)
      ? CupertinoSwitch(
          value: value,
          activeTrackColor: forest,
          onChanged: onChanged,
        )
      : Switch(value: value, onChanged: onChanged);
}

class AdaptiveSlider extends StatelessWidget {
  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.label,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.isFinite ? value.clamp(min, max).toDouble() : min;
    return usesCupertinoUi(context)
        ? CupertinoSlider(
            value: safeValue,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          )
        : Slider(
            value: safeValue,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          );
  }
}

class AdaptiveSegmentedControl<T extends Object> extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.value,
    required this.children,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final Map<T, Widget> children;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (usesCupertinoUi(context)) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        children: children,
        disabledChildren: enabled ? const {} : children.keys.toSet(),
        onValueChanged: (next) {
          if (next != null) onChanged(next);
        },
      );
    }
    return SegmentedButton<T>(
      showSelectedIcon: true,
      segments: [
        for (final entry in children.entries)
          ButtonSegment<T>(value: entry.key, label: entry.value),
      ],
      selected: {value},
      onSelectionChanged: enabled
          ? (values) {
              if (values.isNotEmpty) onChanged(values.first);
            }
          : null,
    );
  }
}

class AdaptiveAction<T> {
  const AdaptiveAction({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final T value;
  final IconData? icon;
  final bool destructive;
}

Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AdaptiveAction<T>> actions,
  String cancelLabel = 'Cancel',
  bool dismissible = true,
}) {
  if (usesCupertinoUi(context)) {
    return showCupertinoModalPopup<T>(
      context: context,
      barrierDismissible: dismissible,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(title),
        message: message == null ? null : Text(message),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: action.destructive,
              onPressed: () => Navigator.pop(sheetContext, action.value),
              child: Text(action.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(cancelLabel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: dismissible,
    enableDrag: dismissible,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: message == null
                  ? null
                  : Text(message, textAlign: TextAlign.center),
            ),
            for (final action in actions)
              ListTile(
                leading: action.icon == null ? null : Icon(action.icon),
                title: Text(
                  action.label,
                  style: action.destructive
                      ? const TextStyle(color: Colors.red)
                      : null,
                ),
                onTap: () => Navigator.pop(sheetContext, action.value),
              ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(cancelLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAdaptiveAlert({
  required BuildContext context,
  required String title,
  required String message,
  String buttonLabel = 'OK',
}) {
  if (usesCupertinoUi(context)) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}

void showAdaptiveMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  if (usesCupertinoUi(context) && error) {
    showAdaptiveAlert(context: context, title: 'PrivacyCam', message: message);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
