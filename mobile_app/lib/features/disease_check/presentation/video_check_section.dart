import 'package:flutter/material.dart';

import '../domain/disease_info.dart';
import '../domain/video_check_result.dart';
import 'video_check_controller.dart';

/// The video white-spot check UI, driven by [VideoCheckController].
class VideoCheckSection extends StatelessWidget {
  const VideoCheckSection({
    required this.controller,
    required this.resultActionsBuilder,
    super.key,
  });

  final VideoCheckController controller;
  final Widget Function(BuildContext context, VideoCheckResult result)?
  resultActionsBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (controller.stage) {
          VideoCheckStage.start => [_VideoStart(controller: controller)],
          VideoCheckStage.checking => [_VideoChecking(controller: controller)],
          VideoCheckStage.result => [
            _VideoResult(
              result: controller.result!,
              resultActionsBuilder: resultActionsBuilder,
              onCheckAnother: controller.reset,
            ),
          ],
          VideoCheckStage.error => [
            _VideoError(
              message: controller.errorMessage!,
              onRetry: controller.retry,
              onStartOver: controller.reset,
            ),
          ],
        },
      ),
    );
  }
}

class _VideoStart extends StatelessWidget {
  const _VideoStart({required this.controller});

  final VideoCheckController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Hold the phone still, 10-20 seconds, fish close and in focus, '
              'good light. Longer clips are checked for the first 30 seconds.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('video-closeup-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('One fish fills the frame'),
          subtitle: const Text(
            'Skip the fish finder and check the whole frame.',
          ),
          value: controller.closeUp,
          onChanged: (value) => controller.closeUp = value,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('video-record'),
          onPressed: controller.recordVideo,
          icon: const Icon(Icons.videocam_rounded),
          label: const Text('Record a video'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('video-choose'),
          onPressed: controller.pickVideo,
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('Choose a video'),
        ),
      ],
    );
  }
}

class _VideoChecking extends StatelessWidget {
  const _VideoChecking({required this.controller});

  final VideoCheckController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.framesTotal;
    final done = controller.framesDone;
    return Column(
      children: [
        const SizedBox(height: 12),
        LinearProgressIndicator(value: total > 0 ? done / total : null),
        const SizedBox(height: 16),
        Text(
          total > 0
              ? 'Checking frame $done of $total'
              : 'Preparing the video...',
          key: const Key('video-progress'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('video-cancel'),
          onPressed: controller.cancel,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _VideoResult extends StatelessWidget {
  const _VideoResult({
    required this.result,
    required this.resultActionsBuilder,
    required this.onCheckAnother,
  });

  final VideoCheckResult result;
  final Widget Function(BuildContext context, VideoCheckResult result)?
  resultActionsBuilder;
  final VoidCallback onCheckAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (
      String title,
      Color background,
      Color foreground,
    ) = switch (result.answer) {
      VideoAnswer.whiteSpotFound => (
        'White spot found',
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      VideoAnswer.healthy => (
        'Healthy',
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      VideoAnswer.notSure => (
        'Not sure',
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
    };

    return Column(
      key: const Key('video-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: background,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.noFishSeen
                      ? 'No fish seen clearly in enough frames. Try a closer or '
                            'longer clip.'
                      : '${result.fish.length} fish checked '
                            '(${result.whiteSpotCount} white spot, '
                            '${result.healthyCount} healthy, '
                            '${result.notSureCount} not sure) over '
                            '${result.framesChecked} frames.',
                  style: TextStyle(color: foreground),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final fish in result.fish) _FishRow(fish: fish),
        const SizedBox(height: 12),
        Card(
          color: colors.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Video checks are experimental. One wrongly judged fish can '
              'change the whole-video answer; check the fish list.',
            ),
          ),
        ),
        if (resultActionsBuilder != null) ...[
          const SizedBox(height: 12),
          resultActionsBuilder!(context, result),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('video-check-another'),
          onPressed: onCheckAnother,
          icon: const Icon(Icons.video_call_outlined),
          label: const Text('Check another video'),
        ),
      ],
    );
  }
}

class _FishRow extends StatelessWidget {
  const _FishRow({required this.fish});

  final VideoFishResult fish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final info = DiseaseInfo.forLabel(
      fish.answer == answerWhiteSpot ? 'white_spot' : 'healthy',
    );
    final Color border = switch (fish.answer) {
      answerWhiteSpot => colors.error,
      answerHealthy => colors.primary,
      _ => colors.tertiary,
    };
    return Card(
      key: Key('video-fish-${fish.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: fish.thumbnail != null
                  ? Image.memory(fish.thumbnail!, fit: BoxFit.cover)
                  : Icon(Icons.pets, color: border),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fish ${fish.id}: ${fish.answer}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'average score ${fish.meanScore.toStringAsFixed(2)} over '
                    '${fish.framesScored} frames',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(info.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({
    required this.message,
    required this.onRetry,
    required this.onStartOver,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('video-try-again'),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
            TextButton(onPressed: onStartOver, child: const Text('Start over')),
          ],
        ),
      ),
    );
  }
}
