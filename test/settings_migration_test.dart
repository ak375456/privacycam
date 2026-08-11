import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installs do not automatically hide ordinary OCR text', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);

    expect(
      settings.autoHideCategories,
      isNot(contains(RedactionCategory.otherText)),
    );
    expect(settings.autoHideCategories, contains(RedactionCategory.email));
    expect(settings.autoHideCategories, contains(RedactionCategory.address));
  });

  test('legacy defaults stop hiding ordinary OCR text after update', () async {
    SharedPreferences.setMockInitialValues({
      'autoHideCategories': [
        for (final category in RedactionCategory.values)
          if (category != RedactionCategory.manual &&
              category != RedactionCategory.person)
            category.name,
      ],
      'autoHideAddressIntroducedV1': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);

    expect(
      settings.autoHideCategories,
      isNot(contains(RedactionCategory.otherText)),
    );
    expect(settings.autoHideCategories, contains(RedactionCategory.email));
  });
}
