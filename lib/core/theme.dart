import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const ink = Color(0xFF12201D);
const forest = Color(0xFF146B55);
const mint = Color(0xFFE4F3EC);
const canvas = Color(0xFFF7F8F5);

ThemeData privacyCamTheme(TargetPlatform platform) => ThemeData(
  useMaterial3: true,
  platform: platform,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    brightness: Brightness.light,
    surface: canvas,
  ),
  scaffoldBackgroundColor: canvas,
  splashFactory: platform == TargetPlatform.iOS ? NoSplash.splashFactory : null,
  cupertinoOverrideTheme: const CupertinoThemeData(
    primaryColor: forest,
    primaryContrastingColor: Colors.white,
    scaffoldBackgroundColor: canvas,
    barBackgroundColor: Color(0xF2F7F8F5),
    textTheme: CupertinoTextThemeData(
      navTitleTextStyle: TextStyle(
        inherit: false,
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      navActionTextStyle: TextStyle(
        inherit: false,
        color: forest,
        fontSize: 17,
      ),
    ),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    backgroundColor: canvas,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
  ),
  textTheme: const TextTheme(
    displaySmall: TextStyle(
      fontWeight: FontWeight.w800,
      color: ink,
      height: 1.08,
    ),
    headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: ink),
    titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
    bodyLarge: TextStyle(height: 1.45, color: Color(0xFF40504B)),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 54),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  ),
);
