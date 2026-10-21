import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/feeding_monitoring.dart';
import '../domain/tank_group.dart';

class FeedingHistoryScreen extends StatefulWidget {
  const FeedingHistoryScreen({
    required this.facility,
    required this.repository,
    this.tankId,
    this.tankName,
    super.key,
  });

  final Facility facility;
  final FacilityRepository repository;
  final String? tankId;
  final String? tankName;

  @override
  State<FeedingHistoryScreen> createState() => _FeedingHistoryScreenState();
}

class _FeedingHistoryScreenState extends State<FeedingHistoryScreen> {
  final List<FeedingHistoryItem> _items = [];
  List<TankGroup> _groups = const [];
  String? _cursor;
  String? _tankId;
  String? _tankName;
  String? _groupId;
  FeedingSource? _source;
  FeedingOutcome? _outcome;
  DateTimeRange? _dates;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _tankId = widget.tankId;
    _tankName = widget.tankName;
    _loadGroups();
    _load();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.repository.listTankGroups(widget.facility.id);
      if (mounted) {
        setState(
          () => _groups = groups.where((item) => !item.archived).toList(),
        );
      }
    } catch (_) {}
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_cursor == null || _loadingMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _cursor = null;
      }
    });
    try {
      final page = await widget.repository.listFeedingHistory(
        facilityId: widget.facility.id,
        tankId: _tankId,
        groupId: _groupId,
        source: _source,
        outcome: _outcome,
        from: _dates?.start,
        to: _dates?.end.add(const Duration(days: 1)),
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dates,
    );
    if (selected != null) {
      setState(() => _dates = selected);
      await _load();
    }
  }

  void _filterTank(FeedingHistoryItem item) {
    setState(() {
      _tankId = item.tankId;
      _tankName = item.tankName;
    });
    _load();
  }

  void _clearFilters() {
    setState(() {
      if (widget.tankId == null) {
        _tankId = null;
        _tankName = null;
      }
      _groupId = null;
      _source = null;
      _outcome = null;
      _dates = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tankName == null ? 'Feeding history' : '$_tankName history',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            groups: _groups,
            tankName: _tankName,
            tankLocked: widget.tankId != null,
            groupId: _groupId,
            source: _source,
            outcome: _outcome,
            dates: _dates,
            onGroup: (value) {
              setState(() => _groupId = value);
              _load();
            },
            onSource: (value) {
              setState(() => _source = value);
              _load();
            },
            onOutcome: (value) {
              setState(() => _outcome = value);
              _load();
            },
            onDates: _pickDates,
            onClearTank: widget.tankId == null && _tankId != null
                ? () {
                    setState(() {
                      _tankId = null;
                      _tankName = null;
                    });
                    _load();
                  }
                : null,
            onClearAll: _clearFilters,
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44),
              const SizedBox(height: 12),
              const Text('Could not load feeding history'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No feeding sessions match these filters.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length + (_cursor == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                key: const Key('feeding-history-load-more'),
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(_loadingMore ? 'Loading…' : 'Load more'),
              ),
            );
          }
          final item = _items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _outcomeColor(context, item.outcome),
                child: Icon(_outcomeIcon(item.outcome), color: Colors.white),
              ),
              title: Text(item.tankName),
              subtitle: Text(
                '${_outcomeLabel(item.outcome)} · ${_date(item.scheduledFor)}'
                '${item.groupName == null ? '' : '\n${item.groupName}'}'
                '${item.reason == null ? '' : '\n${item.reason}'}',
              ),
              isThreeLine: item.groupName != null || item.reason != null,
              trailing: widget.tankId == null && _tankId == null
                  ? IconButton(
                      tooltip: 'Show only this tank',
                      onPressed: () => _filterTank(item),
                      icon: const Icon(Icons.filter_alt_outlined),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.groups,
    required this.tankName,
    required this.tankLocked,
    required this.groupId,
    required this.source,
    required this.outcome,
    required this.dates,
    required this.onGroup,
    required this.onSource,
    required this.onOutcome,
    required this.onDates,
    required this.onClearTank,
    required this.onClearAll,
  });

  final List<TankGroup> groups;
  final String? tankName;
  final bool tankLocked;
  final String? groupId;
  final FeedingSource? source;
  final FeedingOutcome? outcome;
  final DateTimeRange? dates;
  final ValueChanged<String?> onGroup;
  final ValueChanged<FeedingSource?> onSource;
  final ValueChanged<FeedingOutcome?> onOutcome;
  final VoidCallback onDates;
  final VoidCallback? onClearTank;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          if (tankName != null) ...[
            InputChip(
              label: Text('Tank: $tankName'),
              onDeleted: tankLocked ? null : onClearTank,
            ),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<String?>(
            initialValue: groupId,
            onSelected: onGroup,
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All groups')),
              ...groups.map(
                (group) =>
                    PopupMenuItem(value: group.id, child: Text(group.name)),
              ),
            ],
            child: _FilterChipLabel(
              icon: Icons.grid_view_rounded,
              label: groupId == null
                  ? 'All groups'
                  : groups
                            .where((item) => item.id == groupId)
                            .firstOrNull
                            ?.name ??
                        'Group',
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<FeedingSource?>(
            initialValue: source,
            onSelected: onSource,
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('All sources')),
              PopupMenuItem(
                value: FeedingSource.scheduled,
                child: Text('Scheduled'),
              ),
              PopupMenuItem(value: FeedingSource.manual, child: Text('Manual')),
            ],
            child: _FilterChipLabel(
              icon: Icons.schedule_rounded,
              label: source == null ? 'All sources' : _sourceLabel(source!),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<FeedingOutcome?>(
            initialValue: outcome,
            onSelected: onOutcome,
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All outcomes')),
              ...FeedingOutcome.values.map(
                (value) => PopupMenuItem(
                  value: value,
                  child: Text(_outcomeLabel(value)),
                ),
              ),
            ],
            child: _FilterChipLabel(
              icon: Icons.fact_check_outlined,
              label: outcome == null ? 'All outcomes' : _outcomeLabel(outcome!),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(dates == null ? 'Any date' : 'Date range'),
            onPressed: onDates,
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onClearAll, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _FilterChipLabel extends StatelessWidget {
  const _FilterChipLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

String _sourceLabel(FeedingSource source) => switch (source) {
  FeedingSource.scheduled => 'Scheduled',
  FeedingSource.manual => 'Manual',
};

String _outcomeLabel(FeedingOutcome outcome) => switch (outcome) {
  FeedingOutcome.processing => 'Processing',
  FeedingOutcome.commandSent => 'Command sent',
  FeedingOutcome.delivered => 'Delivered',
  FeedingOutcome.skippedLowAppetite => 'Skipped — low appetite',
  FeedingOutcome.skippedLowConfidence => 'Skipped — low confidence',
  FeedingOutcome.skippedStaleObservation => 'Skipped — stale observation',
  FeedingOutcome.skippedCountInconsistent => 'Skipped — count mismatch',
  FeedingOutcome.blockedAutomation => 'Blocked — automation paused',
  FeedingOutcome.blockedCooldown => 'Blocked — cooldown',
  FeedingOutcome.blockedUnhealthyDevice => 'Blocked — hardware',
  FeedingOutcome.blockedCalibration => 'Blocked — calibration',
  FeedingOutcome.failed => 'Failed',
};

IconData _outcomeIcon(FeedingOutcome outcome) => switch (outcome) {
  FeedingOutcome.delivered => Icons.check_rounded,
  FeedingOutcome.commandSent || FeedingOutcome.processing => Icons.sync_rounded,
  FeedingOutcome.failed => Icons.error_outline_rounded,
  _ => Icons.pause_rounded,
};

Color _outcomeColor(BuildContext context, FeedingOutcome outcome) {
  final colors = Theme.of(context).colorScheme;
  return switch (outcome) {
    FeedingOutcome.delivered => Colors.green.shade700,
    FeedingOutcome.failed => colors.error,
    FeedingOutcome.commandSent || FeedingOutcome.processing => colors.primary,
    _ => Colors.orange.shade800,
  };
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
