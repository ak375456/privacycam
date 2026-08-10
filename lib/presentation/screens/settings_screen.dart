import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_links.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const autoHideOptions = [
    (RedactionCategory.face, Icons.face_outlined, 'Faces', 'Detected faces'),
    (
      RedactionCategory.person,
      Icons.accessibility_new_rounded,
      'People (full body)',
      'Visible bodies, including adults and children',
    ),
    (
      RedactionCategory.numberPlate,
      Icons.directions_car_outlined,
      'Number plates',
      'Vehicle registration plates',
    ),
    (
      RedactionCategory.qrCode,
      Icons.qr_code_rounded,
      'QR codes',
      'QR codes are strongly pixelated',
    ),
    (
      RedactionCategory.barcode,
      Icons.view_week_outlined,
      'Barcodes',
      'Product and document barcodes',
    ),
    (
      RedactionCategory.card,
      Icons.credit_card_outlined,
      'Payment card numbers',
      'Credit, debit and ATM card numbers',
    ),
    (
      RedactionCategory.cardSecurityCode,
      Icons.password_outlined,
      'CVV and CVC codes',
      'Card security codes',
    ),
    (
      RedactionCategory.email,
      Icons.alternate_email_rounded,
      'Email addresses',
      'Detected email addresses',
    ),
    (
      RedactionCategory.phone,
      Icons.phone_outlined,
      'Phone numbers',
      'Detected phone numbers',
    ),
    (
      RedactionCategory.address,
      Icons.location_on_outlined,
      'Addresses',
      'Street, delivery and postal addresses',
    ),
    (
      RedactionCategory.url,
      Icons.link_rounded,
      'Website links',
      'Detected URLs and links',
    ),
    (
      RedactionCategory.otherText,
      Icons.text_fields_rounded,
      'Other detected text',
      'All other readable text; this may hide a lot',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final pro = ref.watch(proPurchaseProvider);
    final notifier = ref.read(settingsProvider.notifier);
    void update(AppSettings v) => notifier.update(v);
    return Scaffold(
      appBar: adaptiveNavigationBar(context, title: const Text('Settings')),
      body: usesCupertinoUi(context)
          ? _cupertinoSettings(context, ref, s)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pro.supported) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: mint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          pro.isPro
                              ? Icons.verified_rounded
                              : Icons.workspace_premium_outlined,
                          color: forest,
                        ),
                      ),
                      title: const Text(
                        'PrivacyCam Pro',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        pro.isPro
                            ? 'Lifetime access unlocked'
                            : 'Longer videos, photo batches, and longer PDFs',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/pro'),
                    ),
                  ),
                  const Divider(height: 32),
                ],
                Text(
                  'Hide automatically',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Anything switched on will already be marked “Will hide” after a scan. You can still change individual areas during review.',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 10),
                for (final option in autoHideOptions)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(option.$2),
                    title: Text(option.$3),
                    subtitle: Text(option.$4),
                    value: s.autoHideCategories.contains(option.$1),
                    onChanged: (enabled) {
                      final categories = {...s.autoHideCategories};
                      if (enabled) {
                        categories.add(option.$1);
                      } else {
                        categories.remove(option.$1);
                      }
                      update(s.copyWith(autoHideCategories: categories));
                    },
                  ),
                const Divider(height: 32),
                Text(
                  'Redaction defaults',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: s.faceStyle,
                  decoration: const InputDecoration(
                    labelText: 'Default face style',
                  ),
                  items: RedactionStyle.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (v) => update(s.copyWith(faceStyle: v)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: s.peopleStyle,
                  decoration: const InputDecoration(
                    labelText: 'Default people style',
                  ),
                  items: RedactionStyle.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (v) => update(s.copyWith(peopleStyle: v)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: s.sensitiveStyle,
                  decoration: const InputDecoration(
                    labelText: 'Default sensitive-text style',
                  ),
                  items: RedactionStyle.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (v) => update(s.copyWith(sensitiveStyle: v)),
                ),
                const SizedBox(height: 20),
                Text('Blur strength: ${s.blurStrength.round()}'),
                Slider(
                  value: s.blurStrength,
                  min: AppSettings.minBlurStrength,
                  max: AppSettings.maxBlurStrength,
                  divisions: 31,
                  onChanged: (v) => update(s.copyWith(blurStrength: v)),
                ),
                Text('Pixel size: ${s.pixelSize.round()}'),
                Slider(
                  value: s.pixelSize,
                  min: AppSettings.minPixelSize,
                  max: AppSettings.maxPixelSize,
                  divisions: 38,
                  onChanged: (v) => update(s.copyWith(pixelSize: v)),
                ),
                DropdownButtonFormField(
                  initialValue: s.format,
                  decoration: const InputDecoration(labelText: 'Save format'),
                  items: const [
                    DropdownMenuItem(
                      value: 'source',
                      child: Text('Match source'),
                    ),
                    DropdownMenuItem(value: 'jpg', child: Text('JPEG')),
                    DropdownMenuItem(value: 'png', child: Text('PNG')),
                  ],
                  onChanged: (v) => update(s.copyWith(format: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep temporary edits'),
                  subtitle: const Text('Off is recommended for privacy.'),
                  value: s.keepTemporary,
                  onChanged: (v) => update(s.copyWith(keepTemporary: v)),
                ),
                const Divider(height: 32),
                Text(
                  'Open source',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                const Text(
                  'PrivacyCam’s source code is public under the Apache License 2.0. This lets anyone inspect how photos, videos, and PDFs are handled, independently review privacy and security claims, and contribute fixes or improvements.',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('View source on GitHub'),
                  subtitle: const Text(
                    'Audit, contribute, or build it yourself',
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _openLink(context, AppLinks.sourceCode),
                ),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('PrivacyCam website'),
                  subtitle: const Text('Help and legal information'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _openLink(context, AppLinks.website),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  subtitle: const Text('How PrivacyCam handles your data'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _openLink(context, AppLinks.privacyPolicy),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of service'),
                  subtitle: const Text('Rules for using PrivacyCam'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => _openLink(context, AppLinks.termsOfService),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('About PrivacyCam'),
                  subtitle: Text(
                    'Version 1.1.0 · Photo, video, and PDF privacy review',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.replay_outlined),
                  title: const Text('Reset onboarding'),
                  onTap: () async {
                    await notifier.update(s.copyWith(onboardingDone: false));
                    if (context.mounted) context.go('/onboarding');
                  },
                ),
              ],
            ),
    );
  }

  Widget _cupertinoSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final notifier = ref.read(settingsProvider.notifier);
    final pro = ref.watch(proPurchaseProvider);
    void update(AppSettings value) => notifier.update(value);

    void toggleCategory(RedactionCategory category, bool enabled) {
      final categories = {...settings.autoHideCategories};
      if (enabled) {
        categories.add(category);
      } else {
        categories.remove(category);
      }
      update(settings.copyWith(autoHideCategories: categories));
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: [
        if (pro.supported)
          CupertinoListSection.insetGrouped(
            header: const Text('PRIVACYCAM PRO'),
            footer: Text(
              pro.isPro
                  ? 'Your lifetime Pro purchase is active.'
                  : 'Single photos, videos up to 15 seconds, and PDFs up to 2 pages remain free.',
            ),
            children: [
              CupertinoListTile(
                leading: Icon(
                  pro.isPro
                      ? CupertinoIcons.checkmark_seal_fill
                      : CupertinoIcons.sparkles,
                  color: forest,
                ),
                title: Text(
                  pro.isPro ? 'Pro unlocked' : 'Unlock PrivacyCam Pro',
                ),
                subtitle: Text(
                  pro.isPro
                      ? 'Lifetime access'
                      : 'Longer videos, photo batches, and longer PDFs',
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => context.push('/pro'),
              ),
            ],
          ),
        CupertinoListSection.insetGrouped(
          header: const Text('HIDE AUTOMATICALLY'),
          footer: const Text(
            'Enabled details are marked “Will hide” after scanning. You can still change individual areas during review.',
          ),
          children: [
            for (final option in autoHideOptions)
              CupertinoListTile(
                leading: Icon(option.$2, color: forest),
                title: Text(option.$3),
                subtitle: Text(option.$4),
                trailing: AdaptiveSwitch(
                  value: settings.autoHideCategories.contains(option.$1),
                  onChanged: (enabled) => toggleCategory(option.$1, enabled),
                ),
              ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: const Text('REDACTION DEFAULTS'),
          children: [
            CupertinoListTile(
              title: const Text('Default face style'),
              additionalInfo: Text(_styleLabel(settings.faceStyle)),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final style = await _chooseStyle(
                  context,
                  'Default face style',
                  settings.faceStyle,
                );
                if (style != null) update(settings.copyWith(faceStyle: style));
              },
            ),
            CupertinoListTile(
              title: const Text('Default people style'),
              additionalInfo: Text(_styleLabel(settings.peopleStyle)),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final style = await _chooseStyle(
                  context,
                  'Default people style',
                  settings.peopleStyle,
                );
                if (style != null) {
                  update(settings.copyWith(peopleStyle: style));
                }
              },
            ),
            CupertinoListTile(
              title: const Text('Default sensitive-text style'),
              additionalInfo: Text(_styleLabel(settings.sensitiveStyle)),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final style = await _chooseStyle(
                  context,
                  'Default sensitive-text style',
                  settings.sensitiveStyle,
                );
                if (style != null) {
                  update(settings.copyWith(sensitiveStyle: style));
                }
              },
            ),
            CupertinoListTile(
              title: Text('Blur strength · ${settings.blurStrength.round()}'),
              subtitle: AdaptiveSlider(
                value: settings.blurStrength,
                min: AppSettings.minBlurStrength,
                max: AppSettings.maxBlurStrength,
                divisions: 31,
                onChanged: (value) =>
                    update(settings.copyWith(blurStrength: value)),
              ),
            ),
            CupertinoListTile(
              title: Text('Pixel size · ${settings.pixelSize.round()} px'),
              subtitle: AdaptiveSlider(
                value: settings.pixelSize,
                min: AppSettings.minPixelSize,
                max: AppSettings.maxPixelSize,
                divisions: 38,
                onChanged: (value) =>
                    update(settings.copyWith(pixelSize: value)),
              ),
            ),
            CupertinoListTile(
              title: const Text('Save format'),
              additionalInfo: Text(_formatLabel(settings.format)),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final format = await _chooseFormat(context, settings.format);
                if (format != null) update(settings.copyWith(format: format));
              },
            ),
            CupertinoListTile(
              title: const Text('Keep temporary edits'),
              subtitle: const Text('Off is recommended for privacy.'),
              trailing: AdaptiveSwitch(
                value: settings.keepTemporary,
                onChanged: (value) =>
                    update(settings.copyWith(keepTemporary: value)),
              ),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: const Text('OPEN SOURCE'),
          footer: const Text(
            'Public source lets anyone inspect how photos, videos, and PDFs are handled, independently review privacy and security claims, and contribute fixes or improvements.',
          ),
          children: [
            CupertinoListTile(
              leading: const Icon(Icons.code_rounded, color: forest),
              title: const Text('View source on GitHub'),
              subtitle: const Text('Apache License 2.0'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _openLink(context, AppLinks.sourceCode),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          children: [
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.globe, color: forest),
              title: const Text('PrivacyCam website'),
              subtitle: const Text('Help and legal information'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _openLink(context, AppLinks.website),
            ),
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.hand_raised, color: forest),
              title: const Text('Privacy policy'),
              subtitle: const Text('How PrivacyCam handles your data'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _openLink(context, AppLinks.privacyPolicy),
            ),
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.doc_text, color: forest),
              title: const Text('Terms of service'),
              subtitle: const Text('Rules for using PrivacyCam'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => _openLink(context, AppLinks.termsOfService),
            ),
            const CupertinoListTile(
              leading: Icon(CupertinoIcons.info, color: forest),
              title: Text('About PrivacyCam'),
              subtitle: Text(
                'Version 1.1.0 · Photo, video, and PDF privacy review',
              ),
            ),
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.refresh, color: forest),
              title: const Text('Reset onboarding'),
              onTap: () async {
                await notifier.update(settings.copyWith(onboardingDone: false));
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ],
        ),
      ],
    );
  }

  String _styleLabel(RedactionStyle style) =>
      style.name[0].toUpperCase() + style.name.substring(1);

  String _formatLabel(String format) => switch (format) {
    'jpg' => 'JPEG',
    'png' => 'PNG',
    _ => 'Match source',
  };

  Future<RedactionStyle?> _chooseStyle(
    BuildContext context,
    String title,
    RedactionStyle current,
  ) => showAdaptiveActionSheet<RedactionStyle>(
    context: context,
    title: title,
    message: 'Currently ${_styleLabel(current)}',
    actions: [
      for (final style in RedactionStyle.values)
        AdaptiveAction(label: _styleLabel(style), value: style),
    ],
  );

  Future<String?> _chooseFormat(BuildContext context, String current) =>
      showAdaptiveActionSheet<String>(
        context: context,
        title: 'Save format',
        message: 'Currently ${_formatLabel(current)}',
        actions: const [
          AdaptiveAction(label: 'Match source', value: 'source'),
          AdaptiveAction(label: 'JPEG', value: 'jpg'),
          AdaptiveAction(label: 'PNG', value: 'png'),
        ],
      );

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      final opened = await AppLinks.open(uri);
      if (!opened && context.mounted) {
        showAdaptiveMessage(context, 'Could not open this link.', error: true);
      }
    } catch (_) {
      if (context.mounted) {
        showAdaptiveMessage(context, 'Could not open this link.', error: true);
      }
    }
  }
}
