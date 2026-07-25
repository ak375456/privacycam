import 'package:url_launcher/url_launcher.dart';

abstract final class AppLinks {
  static final website = Uri.parse(
    'https://ak375456.github.io/privacycam-legal/',
  );
  static final privacyPolicy = Uri.parse(
    'https://ak375456.github.io/privacycam-legal/privacy.html',
  );
  static final termsOfService = Uri.parse(
    'https://ak375456.github.io/privacycam-legal/terms.html',
  );
  static final sourceCode = Uri.parse('https://github.com/ak375456/privacycam');

  static Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
