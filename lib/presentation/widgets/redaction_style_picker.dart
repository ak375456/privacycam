import 'package:flutter/material.dart';

import '../../domain/models.dart';

class RedactionStylePicker extends StatelessWidget {
  const RedactionStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final RedactionStyle value;
  final ValueChanged<RedactionStyle> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: RedactionStyle.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 5),
      itemBuilder: (context, index) {
        final style = RedactionStyle.values[index];
        return ChoiceChip(
          avatar: _avatar(style),
          label: Text(_label(style)),
          selected: value == style,
          onSelected: enabled ? (_) => onChanged(style) : null,
        );
      },
    ),
  );

  Widget _avatar(RedactionStyle style) => switch (style) {
    RedactionStyle.blur => const Icon(Icons.blur_on_outlined, size: 17),
    RedactionStyle.pixelate => const Icon(Icons.grid_4x4_outlined, size: 17),
    RedactionStyle.blackout => const Icon(Icons.crop_square, size: 17),
    RedactionStyle.emoji => const Text('💛', style: TextStyle(fontSize: 15)),
    RedactionStyle.flowers => const Text('🌸', style: TextStyle(fontSize: 15)),
  };

  String _label(RedactionStyle style) => switch (style) {
    RedactionStyle.blur => 'Blur',
    RedactionStyle.pixelate => 'Pixelate',
    RedactionStyle.blackout => 'Blackout',
    RedactionStyle.emoji => 'Emoji',
    RedactionStyle.flowers => 'Flowers',
  };
}
