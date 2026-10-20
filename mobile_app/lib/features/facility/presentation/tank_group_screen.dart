import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/tank_group.dart';
import 'group_feeding_schedule_screen.dart';

class TankGroupScreen extends StatefulWidget {
  const TankGroupScreen({
    required this.facility,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final FacilityRepository repository;

  @override
  State<TankGroupScreen> createState() => _TankGroupScreenState();
}

class _TankGroupScreenState extends State<TankGroupScreen> {
  List<TankGroup> _groups = const [];
  Object? _loadError;
  bool _isLoading = true;

  bool get _isOwner => widget.facility.role == FacilityRole.owner;

  @override
  void initState() {
    super.initState();
    _reload(showLoading: false);
  }

  Future<void> _reload({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final groups = await widget.repository.listTankGroups(widget.facility.id);
      if (mounted) {
        setState(() {
          _groups = groups;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = error;
        });
      }
    }
  }

  Future<void> _createGroup() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _TankGroupNameDialog(),
    );
    if (name == null || !mounted) {
      return;
    }
    await _runMutation(
      () => widget.repository.createTankGroup(
        facilityId: widget.facility.id,
        name: name,
      ),
      successMessage: '$name created',
    );
  }

  Future<void> _renameGroup(TankGroup group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TankGroupNameDialog(existingName: group.name),
    );
    if (name == null || !mounted || name == group.name) {
      return;
    }
    await _runMutation(
      () => widget.repository.renameTankGroup(
        facilityId: widget.facility.id,
        groupId: group.id,
        name: name,
      ),
      successMessage: 'Group renamed to $name',
    );
  }

  Future<void> _archiveGroup(TankGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive tank group?'),
        content: Text(
          '${group.name} will remain in the history but cannot receive tanks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-archive-group'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runMutation(
      () => widget.repository.archiveTankGroup(
        facilityId: widget.facility.id,
        groupId: group.id,
      ),
      successMessage: '${group.name} archived',
    );
  }

  Future<void> _openSchedule(TankGroup group) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupFeedingScheduleScreen(
          facility: widget.facility,
          group: group,
          repository: widget.repository,
        ),
      ),
    );
    if (changed == true) await _reload(showLoading: false);
  }

  Future<void> _runMutation(
    Future<TankGroup> Function() mutation, {
    required String successMessage,
  }) async {
    try {
      await mutation();
      if (mounted) {
        _showMessage(successMessage);
        await _reload(showLoading: false);
      }
    } on FacilityException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('The tank group could not be updated. Try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tank groups')),
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              key: const Key('add-tank-group-button'),
              onPressed: _createGroup,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add group'),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _loadError;
    if (error != null) {
      return _GroupError(
        message: error is FacilityException
            ? error.message
            : 'Tank groups could not be loaded.',
        onRetry: () => _reload(),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _reload(showLoading: false),
      child: _groups.isEmpty
          ? _EmptyGroups(isOwner: _isOwner)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
              itemCount: _groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _GroupCard(
                group: _groups[index],
                timeZone: widget.facility.timeZone,
                isOwner: _isOwner,
                onSchedule: () => _openSchedule(_groups[index]),
                onRename: () => _renameGroup(_groups[index]),
                onArchive: () => _archiveGroup(_groups[index]),
              ),
            ),
    );
  }
}

enum _GroupAction { schedule, rename, archive }

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.timeZone,
    required this.isOwner,
    required this.onSchedule,
    required this.onRename,
    required this.onArchive,
  });

  final TankGroup group;
  final String timeZone;
  final bool isOwner;
  final VoidCallback onSchedule;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final countLabel = group.tankCount == 1
        ? '1 tank'
        : '${group.tankCount} tanks';
    return Card(
      key: Key('tank-group-${group.id}'),
      child: ListTile(
        onTap: onSchedule,
        leading: CircleAvatar(
          child: Icon(
            group.archived
                ? Icons.inventory_2_outlined
                : Icons.grid_view_rounded,
          ),
        ),
        title: Text(group.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.archived ? '$countLabel · Archived' : countLabel),
            Text(
              group.feedingTimes.isEmpty
                  ? 'No feeding schedule'
                  : '${group.feedingTimes.join(', ')} · '
                        '${group.feedingAutomationEnabled ? 'Automatic' : 'Paused'}',
            ),
            Text(timeZone.replaceAll('_', ' ')),
          ],
        ),
        isThreeLine: true,
        trailing: isOwner && !group.archived
            ? PopupMenuButton<_GroupAction>(
                key: Key('tank-group-actions-${group.id}'),
                tooltip: 'Group actions',
                onSelected: (action) {
                  switch (action) {
                    case _GroupAction.schedule:
                      onSchedule();
                      break;
                    case _GroupAction.rename:
                      onRename();
                      break;
                    case _GroupAction.archive:
                      onArchive();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _GroupAction.schedule,
                    child: Text('Feeding schedule'),
                  ),
                  const PopupMenuItem(
                    value: _GroupAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _GroupAction.archive,
                    enabled: group.tankCount == 0,
                    child: Text(
                      group.tankCount == 0
                          ? 'Archive'
                          : 'Move tanks before archiving',
                    ),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _TankGroupNameDialog extends StatefulWidget {
  const _TankGroupNameDialog({this.existingName});

  final String? existingName;

  @override
  State<_TankGroupNameDialog> createState() => _TankGroupNameDialogState();
}

class _TankGroupNameDialogState extends State<_TankGroupNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existingName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRenaming = widget.existingName != null;
    return AlertDialog(
      title: Text(isRenaming ? 'Rename tank group' : 'Add tank group'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('tank-group-name-field'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(80)],
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'Nursery tanks',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter a group name.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-tank-group-button'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: Text(isRenaming ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 72),
        Icon(
          Icons.grid_view_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'No tank groups yet',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          isOwner
              ? 'Add a group to organize tanks by room, rack, or life stage.'
              : 'An owner has not added any tank groups yet.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _GroupError extends StatelessWidget {
  const _GroupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
