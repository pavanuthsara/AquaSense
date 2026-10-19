import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_team.dart';

class FacilityTeamScreen extends StatefulWidget {
  const FacilityTeamScreen({
    required this.facility,
    required this.repository,
    super.key,
  });

  final Facility facility;
  final FacilityRepository repository;

  @override
  State<FacilityTeamScreen> createState() => _FacilityTeamScreenState();
}

class _FacilityTeamScreenState extends State<FacilityTeamScreen> {
  late Future<_TeamData> _data;

  bool get _isOwner => widget.facility.role == FacilityRole.owner;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_TeamData> _load() async {
    final members = await widget.repository.listMembers(widget.facility.id);
    final invitations = _isOwner
        ? await widget.repository.listFacilityInvitations(widget.facility.id)
        : const <FacilityInvitation>[];
    return _TeamData(members: members, invitations: invitations);
  }

  void _reload() {
    setState(() => _data = _load());
  }

  Future<void> _inviteWorker() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => const _InviteWorkerDialog(),
    );
    if (email == null || !mounted) {
      return;
    }
    try {
      await widget.repository.inviteWorker(
        facilityId: widget.facility.id,
        email: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation sent to ${email.toLowerCase()}')),
        );
        _reload();
      }
    } on FacilityException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('The invitation could not be sent. Try again.');
    }
  }

  Future<void> _revokeInvitation(FacilityInvitation invitation) async {
    try {
      await widget.repository.revokeInvitation(
        facilityId: widget.facility.id,
        invitationId: invitation.id,
      );
      if (mounted) {
        _reload();
      }
    } on FacilityException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _removeWorker(FacilityMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove worker?'),
        content: Text(
          '${member.displayName} will immediately lose access to '
          '${widget.facility.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.repository.removeWorker(
        facilityId: widget.facility.id,
        membershipId: member.id,
      );
      if (mounted) {
        _reload();
      }
    } on FacilityException catch (error) {
      _showError(error.message);
    }
  }

  void _showError(String message) {
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
      appBar: AppBar(
        title: Text(_isOwner ? 'Workers' : 'Aquarium team'),
        actions: [
          if (_isOwner)
            IconButton(
              key: const Key('invite-worker-button'),
              tooltip: 'Invite worker',
              onPressed: _inviteWorker,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
      ),
      body: FutureBuilder<_TeamData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _TeamError(
              message: error is FacilityException
                  ? error.message
                  : 'The aquarium team could not be loaded.',
              onRetry: _reload,
            );
          }
          final data = snapshot.requireData;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _data;
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Team members',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ...data.members.map(
                  (member) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          member.displayName.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(member.displayName),
                      subtitle: Text(
                        '${member.email}\n'
                        '${member.role == FacilityRole.owner ? 'Owner' : 'Worker'}',
                      ),
                      isThreeLine: true,
                      trailing: _isOwner && member.role == FacilityRole.worker
                          ? IconButton(
                              key: Key('remove-worker-${member.id}'),
                              tooltip: 'Remove worker',
                              onPressed: () => _removeWorker(member),
                              icon: const Icon(Icons.person_remove_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
                if (_isOwner) ...[
                  const SizedBox(height: 26),
                  Text(
                    'Invitations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (data.invitations.isEmpty)
                    const Text('No invitations have been sent.'),
                  ...data.invitations.map(
                    (invitation) => Card(
                      child: ListTile(
                        title: Text(invitation.email),
                        subtitle: Text(_statusLabel(invitation.status)),
                        trailing:
                            invitation.status ==
                                FacilityInvitationStatus.pending
                            ? IconButton(
                                key: Key('revoke-invitation-${invitation.id}'),
                                tooltip: 'Revoke invitation',
                                onPressed: () => _revokeInvitation(invitation),
                                icon: const Icon(Icons.cancel_outlined),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(FacilityInvitationStatus status) => switch (status) {
    FacilityInvitationStatus.pending => 'Pending · expires in 7 days',
    FacilityInvitationStatus.accepted => 'Accepted',
    FacilityInvitationStatus.revoked => 'Revoked',
    FacilityInvitationStatus.expired => 'Expired',
  };
}

class _InviteWorkerDialog extends StatefulWidget {
  const _InviteWorkerDialog();

  @override
  State<_InviteWorkerDialog> createState() => _InviteWorkerDialogState();
}

class _InviteWorkerDialogState extends State<_InviteWorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite a worker'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('worker-email-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: [LengthLimitingTextInputFormatter(320)],
          decoration: const InputDecoration(
            labelText: 'Verified Google email',
            hintText: 'worker@example.com',
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid email address.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text('Send invitation'),
        ),
      ],
    );
  }
}

class _TeamError extends StatelessWidget {
  const _TeamError({required this.message, required this.onRetry});

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

class _TeamData {
  const _TeamData({required this.members, required this.invitations});

  final List<FacilityMember> members;
  final List<FacilityInvitation> invitations;
}
