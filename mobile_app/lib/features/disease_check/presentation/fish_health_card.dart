import 'package:flutter/material.dart';

import '../../facility/presentation/selected_facility_scope.dart';
import '../data/video_check_runner.dart';
import '../domain/video_save_mapping.dart';
import 'disease_check_scope.dart';
import 'disease_check_screen.dart';
import 'disease_history_screen.dart';
import 'save_disease_check_panel.dart';

/// Home-screen entry to the fish health check and its history.
///
/// It finds everything it needs through scopes, so the home screen only has
/// to place it.
class FishHealthCard extends StatelessWidget {
  const FishHealthCard({super.key});

  void _openCheck(BuildContext context) {
    final scope = DiseaseCheckScope.of(context);
    final facility = SelectedFacilityScope.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiseaseCheckScreen(
          classifier: scope.classifier,
          photoSource: scope.photoSource,
          resultActionsBuilder: (context, prediction) => SaveDiseaseCheckPanel(
            facilityId: facility.id,
            prediction: prediction,
            repository: scope.repository,
          ),
          videoRunner: VideoCheckRunner(
            detector: scope.fishDetector,
            classifier: scope.fishCropClassifier,
            extractor: scope.frameExtractor,
          ),
          videoSource: scope.videoSource,
          videoResultActionsBuilder: (context, result) => SaveDiseaseCheckPanel(
            facilityId: facility.id,
            prediction: videoResultToPrediction(result),
            repository: scope.repository,
            initialNote: videoResultNote(result),
          ),
        ),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    final scope = DiseaseCheckScope.of(context);
    final facility = SelectedFacilityScope.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiseaseHistoryScreen(
          facilityId: facility.id,
          facilityName: facility.name,
          repository: scope.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('fish-health-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fish health check',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Photograph a guppy to check it for white spot.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('open-disease-check'),
              onPressed: () => _openCheck(context),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Check fish health'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('open-disease-history'),
              onPressed: () => _openHistory(context),
              icon: const Icon(Icons.history_rounded),
              label: const Text('History'),
            ),
          ],
        ),
      ),
    );
  }
}
