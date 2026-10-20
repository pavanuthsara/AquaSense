import 'package:flutter/material.dart';

/// Plain-language information shown for each model label.
///
/// To support a new class (for example fin rot), add one entry here and
/// replace the two model asset files. Nothing else needs to change.
class DiseaseInfo {
  const DiseaseInfo({
    required this.label,
    required this.displayName,
    required this.description,
    required this.advice,
    required this.icon,
    required this.isDisease,
  });

  /// Label exactly as written in the model's labels file.
  final String label;
  final String displayName;
  final String description;
  final List<String> advice;
  final IconData icon;

  /// False for "healthy"; used to choose calm or warning colours.
  final bool isDisease;

  static const healthy = DiseaseInfo(
    label: 'healthy',
    displayName: 'Healthy',
    description: 'No signs of white spot were found on this fish.',
    advice: [
      'Keep checking your fish regularly, especially new arrivals.',
      'Look at the fins and body in good light if the fish acts unwell.',
    ],
    icon: Icons.check_circle_rounded,
    isDisease: false,
  );

  static const whiteSpot = DiseaseInfo(
    label: 'white_spot',
    displayName: 'White spot',
    description:
        'Small white dots, like grains of salt, on the body or fins. White '
        'spot (Ich) is a parasite that spreads quickly between fish.',
    advice: [
      'Move the fish to a separate tank if you can.',
      'Check the other fish in the same tank.',
      'Raise the water temperature slowly and keep the water clean.',
      'Ask an experienced farmer or vet before using any medicine.',
    ],
    icon: Icons.bug_report_rounded,
    isDisease: true,
  );

  static const known = [healthy, whiteSpot];

  /// Information for a label, or a generic entry if the label is new.
  static DiseaseInfo forLabel(String label) {
    for (final info in known) {
      if (info.label == label) {
        return info;
      }
    }
    return DiseaseInfo(
      label: label,
      displayName: _readable(label),
      description: 'The model reported "$label".',
      advice: const ['Ask an experienced farmer or vet to check the fish.'],
      icon: Icons.help_outline_rounded,
      isDisease: true,
    );
  }

  static String _readable(String label) {
    final words = label.split('_').where((word) => word.isNotEmpty);
    final text = words.join(' ');
    if (text.isEmpty) {
      return label;
    }
    return text[0].toUpperCase() + text.substring(1);
  }
}
