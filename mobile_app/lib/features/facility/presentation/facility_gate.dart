import 'package:flutter/material.dart';

import '../../auth/presentation/authentication_scope.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_selection_store.dart';
import 'facility_home_screen.dart';
import 'facility_repository_scope.dart';
import 'facility_selection_controller.dart';
import 'facility_selection_store_scope.dart';
import 'facility_setup_screen.dart';
import 'facility_team_screen.dart';
import 'pending_invitations_screen.dart';
import 'selected_facility_scope.dart';
import 'tank_group_screen.dart';
import 'tank_list_screen.dart';

class FacilityGate extends StatefulWidget {
  const FacilityGate({super.key});

  @override
  State<FacilityGate> createState() => _FacilityGateState();
}

class _FacilityGateState extends State<FacilityGate> {
  FacilityRepository? _repository;
  FacilitySelectionStore? _selectionStore;
  String? _userId;
  FacilitySelectionController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = FacilityRepositoryScope.of(context);
    final selectionStore = FacilitySelectionStoreScope.of(context);
    final userId = AuthenticationScope.of(context).user?.id;
    if (userId == null ||
        (_repository == repository &&
            _selectionStore == selectionStore &&
            _userId == userId)) {
      return;
    }

    _controller?.dispose();
    _repository = repository;
    _selectionStore = selectionStore;
    _userId = userId;
    _controller = FacilitySelectionController(
      repository: repository,
      selectionStore: selectionStore,
      userId: userId,
    )..initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openAddFacility() async {
    final controller = _controller!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => FacilitySetupScreen(
          repository: _repository!,
          isFirstFacility: controller.facilities.isEmpty,
          onCreated: (facility) async {
            await controller.addAndSelect(facility);
            if (routeContext.mounted) {
              Navigator.of(routeContext).pop();
            }
          },
        ),
      ),
    );
  }

  Future<void> _openTeam() async {
    final facility = _controller!.selectedFacility!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            FacilityTeamScreen(facility: facility, repository: _repository!),
      ),
    );
  }

  Future<void> _openTankGroups() async {
    final facility = _controller!.selectedFacility!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TankGroupScreen(facility: facility, repository: _repository!),
      ),
    );
  }

  Future<void> _openTanks() async {
    final facility = _controller!.selectedFacility!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TankListScreen(facility: facility, repository: _repository!),
      ),
    );
  }

  Future<void> _openInvitations() async {
    final controller = _controller!;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => PendingInvitationsScreen(
            invitations: controller.pendingInvitations,
            isAccepting: controller.isSwitching,
            onAccept: (invitation) async {
              final accepted = await controller.acceptInvitation(invitation);
              if (accepted && routeContext.mounted) {
                Navigator.of(routeContext).pop();
              }
              return accepted;
            },
          ),
        ),
      ),
    );
  }

  void _queueNotice(FacilitySelectionController controller, String notice) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.notice != notice) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
      controller.clearNotice();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const _FacilityLoadingScreen();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final notice = controller.notice;
        if (notice != null) {
          _queueNotice(controller, notice);
        }
        if (controller.isLoading) {
          return const _FacilityLoadingScreen();
        }
        if (controller.loadError != null) {
          return _FacilityLoadErrorScreen(
            message: controller.loadError!,
            onRetry: controller.retry,
          );
        }

        final selectedFacility = controller.selectedFacility;
        if (selectedFacility == null) {
          if (controller.pendingInvitations.isNotEmpty) {
            return PendingInvitationsScreen(
              invitations: controller.pendingInvitations,
              isAccepting: controller.isSwitching,
              onAccept: controller.acceptInvitation,
              onCreateFacility: _openAddFacility,
            );
          }
          return FacilitySetupScreen(
            repository: _repository!,
            onCreated: controller.addAndSelect,
          );
        }

        return SelectedFacilityScope(
          key: ValueKey('facility-scope-${selectedFacility.id}'),
          facility: selectedFacility,
          child: FacilityHomeScreen(
            key: ValueKey('facility-home-${selectedFacility.id}'),
            facilities: controller.facilities,
            isSwitching: controller.isSwitching,
            onFacilitySelected: controller.select,
            onAddFacility: _openAddFacility,
            onOpenTeam: _openTeam,
            onOpenTankGroups: _openTankGroups,
            onOpenTanks: _openTanks,
            onOpenInvitations: _openInvitations,
            pendingInvitationCount: controller.pendingInvitations.length,
            repository: _repository!,
          ),
        );
      },
    );
  }
}

class _FacilityLoadingScreen extends StatelessWidget {
  const _FacilityLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.water_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            const Text('Loading your aquariums'),
            const SizedBox(height: 18),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _FacilityLoadErrorScreen extends StatelessWidget {
  const _FacilityLoadErrorScreen({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 18),
                Text(
                  'Could not load aquariums',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
