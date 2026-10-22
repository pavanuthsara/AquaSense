import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/video_check_runner.dart';
import '../domain/disease_classifier.dart';
import '../domain/disease_info.dart';
import '../domain/disease_prediction.dart';
import '../domain/fish_photo_source.dart';
import '../domain/fish_video_source.dart';
import '../domain/video_check_result.dart';
import 'disease_check_controller.dart';
import 'video_check_controller.dart';
import 'video_check_section.dart';

enum _CheckMode { photo, video }

/// Take or pick a photo of one fish, or a video of a tank, and see what the
/// model thinks. Video mode is only shown when its parts are supplied.
class DiseaseCheckScreen extends StatefulWidget {
  const DiseaseCheckScreen({
    required this.classifier,
    required this.photoSource,
    this.resultActionsBuilder,
    this.videoRunner,
    this.videoSource,
    this.videoResultActionsBuilder,
    super.key,
  });

  final DiseaseClassifier classifier;
  final FishPhotoSource photoSource;

  /// Extra widgets under a photo result, such as saving it to history.
  final Widget Function(BuildContext context, DiseasePrediction prediction)?
  resultActionsBuilder;

  /// Supplying both of these turns on video mode.
  final VideoCheckRunner? videoRunner;
  final FishVideoSource? videoSource;

  /// Extra widgets under a video result, such as saving it to history.
  final Widget Function(BuildContext context, VideoCheckResult result)?
  videoResultActionsBuilder;

  @override
  State<DiseaseCheckScreen> createState() => _DiseaseCheckScreenState();
}

class _DiseaseCheckScreenState extends State<DiseaseCheckScreen> {
  late final DiseaseCheckController _controller;
  VideoCheckController? _videoController;
  _CheckMode _mode = _CheckMode.photo;

  bool get _videoEnabled => _videoController != null;

  @override
  void initState() {
    super.initState();
    _controller = DiseaseCheckController(
      classifier: widget.classifier,
      photoSource: widget.photoSource,
    );
    if (widget.videoRunner != null && widget.videoSource != null) {
      _videoController = VideoCheckController(
        runner: widget.videoRunner!,
        videoSource: widget.videoSource!,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check fish health')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_videoEnabled) ...[
                SegmentedButton<_CheckMode>(
                  key: const Key('disease-mode-toggle'),
                  segments: const [
                    ButtonSegment(
                      value: _CheckMode.photo,
                      icon: Icon(Icons.photo_camera_rounded),
                      label: Text('Photo'),
                    ),
                    ButtonSegment(
                      value: _CheckMode.video,
                      icon: Icon(Icons.videocam_rounded),
                      label: Text('Video'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      setState(() => _mode = selection.first),
                ),
                const SizedBox(height: 16),
              ],
              if (_mode == _CheckMode.photo)
                _buildPhotoContent()
              else
                VideoCheckSection(
                  controller: _videoController!,
                  resultActionsBuilder: widget.videoResultActionsBuilder,
                ),
              const SizedBox(height: 24),
              const _ScreeningDisclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoContent() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...switch (_controller.stage) {
            DiseaseCheckStage.start => [
              const _PhotoTips(),
              const SizedBox(height: 20),
              _PhotoButtons(controller: _controller),
            ],
            DiseaseCheckStage.checking => [
              _PhotoPreview(photo: _controller.photo),
              const SizedBox(height: 24),
              const _CheckingIndicator(),
            ],
            DiseaseCheckStage.result => [
              _PhotoPreview(photo: _controller.photo),
              const SizedBox(height: 16),
              _ResultCard(prediction: _controller.prediction!),
              if (_controller.prediction!.isUncertain) ...[
                const SizedBox(height: 16),
                const _PhotoTips(compact: true),
              ],
              if (widget.resultActionsBuilder != null) ...[
                const SizedBox(height: 16),
                widget.resultActionsBuilder!(context, _controller.prediction!),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('disease-check-another'),
                onPressed: _controller.reset,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Check another fish'),
              ),
            ],
            DiseaseCheckStage.error => [
              if (_controller.photo != null) ...[
                _PhotoPreview(photo: _controller.photo),
                const SizedBox(height: 16),
              ],
              _ErrorCard(
                message: _controller.errorMessage!,
                onRetry: _controller.photo == null
                    ? _controller.reset
                    : _controller.retry,
                onStartOver: _controller.reset,
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _PhotoTips extends StatelessWidget {
  const _PhotoTips({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tips = [
      (
        Icons.crop_free_rounded,
        'One fish, close up, filling most of the photo',
      ),
      (Icons.wb_sunny_outlined, 'Good light, with no glare on the glass'),
      (Icons.center_focus_strong_outlined, 'Sharp, not blurry'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) ...[
              Icon(
                Icons.health_and_safety_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Check a guppy for white spot',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The check runs on this phone, so it works without internet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              compact ? 'For a better photo' : 'For a good result',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoButtons extends StatelessWidget {
  const _PhotoButtons({required this.controller});

  final DiseaseCheckController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('disease-take-photo'),
          onPressed: controller.takePhoto,
          icon: const Icon(Icons.photo_camera_rounded),
          label: const Text('Take photo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('disease-pick-photo'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: controller.pickFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from gallery'),
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo});

  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final bytes = photo;
    if (bytes == null) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: Colors.black,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckingIndicator extends StatelessWidget {
  const _CheckingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 14),
        Text('Checking the fish…'),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.prediction});

  final DiseasePrediction prediction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final uncertain = prediction.isUncertain;
    final info = DiseaseInfo.forLabel(prediction.topLabel);

    final (Color background, Color foreground, IconData icon) = uncertain
        ? (colors.surfaceContainerHigh, colors.onSurface, Icons.help_rounded)
        : info.isDisease
        ? (colors.errorContainer, colors.onErrorContainer, info.icon)
        : (colors.primaryContainer, colors.onPrimaryContainer, info.icon);

    return Card(
      key: const Key('disease-result-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: background,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, size: 36, color: foreground),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uncertain ? 'Not sure' : info.displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        uncertain
                            ? 'Take another photo'
                            : 'Model result for this photo',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uncertain
                      ? 'The model could not decide between the possible '
                            'results. A closer, sharper photo of one fish '
                            'usually helps.'
                      : info.description,
                ),
                if (!uncertain) ...[
                  const SizedBox(height: 14),
                  Text(
                    'What to do',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final step in info.advice)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  '),
                          Expanded(child: Text(step)),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Model scores',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final score in prediction.scores) _ScoreBar(score: score),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.score});

  final LabelScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (score.score * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(DiseaseInfo.forLabel(score.label).displayName),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: score.score,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text('$percent%', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'The check did not work',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('disease-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
            TextButton(
              onPressed: onStartOver,
              child: const Text('Use a different photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreeningDisclaimer extends StatelessWidget {
  const _ScreeningDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Screening aid only, not a diagnosis. The model checks for white '
            'spot only and can be wrong, even when its score is high.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
