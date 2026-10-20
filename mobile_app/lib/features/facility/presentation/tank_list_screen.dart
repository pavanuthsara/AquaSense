import 'package:flutter/material.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank.dart';
import '../domain/tank_group.dart';
import 'tank_detail_screen.dart';
import 'tank_form_screen.dart';

class TankListScreen extends StatefulWidget {
  const TankListScreen({
    required this.facility,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final FacilityRepository repository;

  @override
  State<TankListScreen> createState() => _TankListScreenState();
}

class _TankListScreenState extends State<TankListScreen> {
  static const _all = '__all__';
  static const _unassigned = '__unassigned__';
  final _search = TextEditingController();
  List<TankGroup> _groups = const [];
  List<String> _tags = const [];
  List<Tank> _tanks = const [];
  String _status = _all;
  String _group = _all;
  String _tag = _all;
  int _page = 0;
  int _totalItems = 0;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  bool get _isOwner => widget.facility.role == FacilityRole.owner;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final results = await Future.wait([
        widget.repository.listTankGroups(widget.facility.id),
        widget.repository.listTankTags(widget.facility.id),
      ]);
      _groups = results[0] as List<TankGroup>;
      _tags = results[1] as List<String>;
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  TankStatus? get _selectedStatus => switch (_status) {
    'active' => TankStatus.active,
    'paused' => TankStatus.paused,
    'archived' => TankStatus.archived,
    _ => null,
  };

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listTanks(
        facilityId: widget.facility.id,
        page: 0,
        search: _search.text,
        status: _selectedStatus,
        groupId: _group == _all || _group == _unassigned ? null : _group,
        unassigned: _group == _unassigned,
        tag: _tag == _all ? null : _tag,
      );
      if (mounted) {
        setState(() {
          _tanks = page.items;
          _page = page.page;
          _totalItems = page.totalItems;
          _hasNext = page.hasNextPage;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasNext || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.listTanks(
        facilityId: widget.facility.id,
        page: _page + 1,
        search: _search.text,
        status: _selectedStatus,
        groupId: _group == _all || _group == _unassigned ? null : _group,
        unassigned: _group == _unassigned,
        tag: _tag == _all ? null : _tag,
      );
      if (mounted) {
        setState(() {
          _tanks = List.unmodifiable([..._tanks, ...page.items]);
          _page = page.page;
          _hasNext = page.hasNextPage;
        });
      }
    } on FacilityException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openForm([Tank? tank]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TankFormScreen(
          facility: widget.facility,
          repository: widget.repository,
          groups: _groups,
          tank: tank,
        ),
      ),
    );
    if (changed == true) {
      _tags = await widget.repository.listTankTags(widget.facility.id);
      await _refresh();
    }
  }

  Future<void> _openDetail(Tank tank) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TankDetailScreen(
          facility: widget.facility,
          tankId: tank.id,
          repository: widget.repository,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _archive(Tank tank) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive tank?'),
        content: Text('${tank.name} will be removed from active operations.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-list-archive-tank'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.archiveTank(
        facilityId: widget.facility.id,
        tankId: tank.id,
      );
      await _refresh();
    } on FacilityException catch (error) {
      _message(error.message);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tanks')),
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              key: const Key('add-tank-button'),
              onPressed: _loading ? null : _openForm,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add tank'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('tank-search-field'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _refresh(),
                decoration: InputDecoration(
                  hintText: 'Search tank name or code',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    key: const Key('tank-search-button'),
                    tooltip: 'Search',
                    onPressed: _refresh,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterDropdown(
                    key: const Key('tank-status-filter'),
                    value: _status,
                    label: 'Status',
                    items: const {
                      _all: 'Current',
                      'active': 'Active',
                      'paused': 'Paused',
                      'archived': 'Archived',
                    },
                    onChanged: (value) {
                      setState(() => _status = value);
                      _refresh();
                    },
                  ),
                  const SizedBox(width: 10),
                  _FilterDropdown(
                    key: const Key('tank-group-filter'),
                    value: _group,
                    label: 'Group',
                    items: {
                      _all: 'All groups',
                      _unassigned: 'Unassigned',
                      for (final group in _groups.where(
                        (group) => !group.archived,
                      ))
                        group.id: group.name,
                    },
                    onChanged: (value) {
                      setState(() => _group = value);
                      _refresh();
                    },
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _FilterDropdown(
                      key: const Key('tank-tag-filter'),
                      value: _tag,
                      label: 'Tag',
                      items: {
                        _all: 'All tags',
                        for (final tag in _tags) tag: tag,
                      },
                      onChanged: (value) {
                        setState(() => _tag = value);
                        _refresh();
                      },
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$_totalItems tanks'),
              ),
            ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      final error = _error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is FacilityException
                    ? error.message
                    : 'Tanks could not be loaded.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _initialize,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tanks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 56),
          Icon(
            Icons.water_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No matching tanks',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _isOwner
                ? 'Add a tank or adjust the search and filters.'
                : 'Adjust the search and filters.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
        itemCount: _tanks.length + (_hasNext ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _tanks.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                key: const Key('load-more-tanks-button'),
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? 'Loading…' : 'Load more'),
              ),
            );
          }
          final tank = _tanks[index];
          return Card(
            child: ListTile(
              key: Key('tank-${tank.id}'),
              onTap: () => _openDetail(tank),
              leading: CircleAvatar(child: Text(tank.code.characters.first)),
              title: Text(tank.name),
              subtitle: Text(
                '${tank.code} · ${tank.groupName ?? 'Unassigned'}\n'
                '${_statusLabel(tank.status)} · ${tank.expectedGuppyCount} expected',
              ),
              isThreeLine: true,
              trailing: _isOwner && tank.status != TankStatus.archived
                  ? PopupMenuButton<String>(
                      key: Key('tank-actions-${tank.id}'),
                      onSelected: (action) {
                        if (action == 'edit') _openForm(tank);
                        if (action == 'archive') _archive(tank);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'archive', child: Text('Archive')),
                      ],
                    )
                  : const Icon(Icons.chevron_right_rounded),
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(TankStatus status) => switch (status) {
    TankStatus.active => 'Active',
    TankStatus.paused => 'Paused',
    TankStatus.archived => 'Archived',
  };
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String value;
  final String label;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            isExpanded: true,
            items: items.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => onChanged(value!),
          ),
        ),
      ),
    );
  }
}
