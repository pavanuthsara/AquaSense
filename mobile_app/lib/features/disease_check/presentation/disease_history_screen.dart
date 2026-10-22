import 'package:flutter/material.dart';

import '../domain/disease_check_record.dart';
import '../domain/disease_check_repository.dart';
import '../domain/disease_info.dart';

/// Past disease checks for one aquarium, newest first.
class DiseaseHistoryScreen extends StatefulWidget {
  const DiseaseHistoryScreen({
    required this.facilityId,
    required this.facilityName,
    required this.repository,
    super.key,
  });

  final String facilityId;
  final String facilityName;
  final DiseaseCheckRepository repository;

  @override
  State<DiseaseHistoryScreen> createState() => _DiseaseHistoryScreenState();
}

class _DiseaseHistoryScreenState extends State<DiseaseHistoryScreen> {
  static const _pageSize = 50;

  List<DiseaseCheckRecord>? _records;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await widget.repository.listChecks(
        facilityId: widget.facilityId,
        limit: _pageSize,
      );
      if (mounted) {
        setState(() {
          _records = records;
          _loading = false;
        });
      }
    } on DiseaseCheckException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fish health history')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading && _records == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _records == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('Could not load history', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final records = _records ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: records.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No checks saved yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Saved fish health checks for ${widget.facilityName} '
                  'will appear here.',
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _HistoryTile(record: records[index]),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final DiseaseCheckRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final info = DiseaseInfo.forLabel(record.predictedLabel);
    final (String label, Color background, Color foreground) = record.uncertain
        ? ('Not sure', colors.surfaceContainerHigh, colors.onSurface)
        : info.isDisease
        ? (info.displayName, colors.errorContainer, colors.onErrorContainer)
        : (
            info.displayName,
            colors.primaryContainer,
            colors.onPrimaryContainer,
          );

    final details = [
      if (record.tankLabel != null) record.tankLabel!,
      'by ${record.checkedByName}',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${(record.confidence * 100).round()}%'),
                if (record.modelVersion.startsWith('guppy-video')) ...[
                  const SizedBox(width: 8),
                  Container(
                    key: const Key('video-chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Video',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _formatTime(record.checkedAt.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(details, style: theme.textTheme.bodyMedium),
            if (record.note != null) ...[
              const SizedBox(height: 4),
              Text(
                record.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
