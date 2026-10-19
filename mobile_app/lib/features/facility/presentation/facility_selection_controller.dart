import 'package:flutter/foundation.dart';

import '../domain/facility.dart';
import '../domain/facility_repository.dart';
import '../domain/facility_selection_store.dart';
import '../domain/facility_team.dart';

class FacilitySelectionController extends ChangeNotifier {
  FacilitySelectionController({
    required FacilityRepository repository,
    required FacilitySelectionStore selectionStore,
    required String userId,
  }) : _repository = repository,
       _selectionStore = selectionStore,
       _userId = userId;

  final FacilityRepository _repository;
  final FacilitySelectionStore _selectionStore;
  final String _userId;

  List<Facility> _facilities = const [];
  List<FacilityInvitation> _pendingInvitations = const [];
  Facility? _selectedFacility;
  String? _loadError;
  String? _notice;
  bool _isLoading = true;
  bool _isSwitching = false;

  List<Facility> get facilities => _facilities;
  List<FacilityInvitation> get pendingInvitations => _pendingInvitations;
  Facility? get selectedFacility => _selectedFacility;
  String? get loadError => _loadError;
  String? get notice => _notice;
  bool get isLoading => _isLoading;
  bool get isSwitching => _isSwitching;

  Future<void> initialize() => _loadFacilities(useSavedSelection: true);

  Future<void> retry() => _loadFacilities(useSavedSelection: true);

  Future<void> refresh() => _loadFacilities(useSavedSelection: false);

  Future<bool> select(Facility facility) async {
    if (_isSwitching || facility.id == _selectedFacility?.id) {
      return facility.id == _selectedFacility?.id;
    }

    _isSwitching = true;
    _notice = null;
    notifyListeners();
    try {
      final verified = await _repository.getFacility(facility.id);
      _replaceFacility(verified);
      _selectedFacility = verified;
      await _saveSelection(verified.id);
      return true;
    } on FacilityException catch (error) {
      if (error.code == 'facility_not_found') {
        await _recoverFromInaccessibleFacility();
      } else {
        _notice = error.message;
      }
      return false;
    } catch (_) {
      _notice = 'The aquarium could not be selected. Try again.';
      return false;
    } finally {
      _isSwitching = false;
      notifyListeners();
    }
  }

  Future<bool> acceptInvitation(FacilityInvitation invitation) async {
    if (_isSwitching) {
      return false;
    }
    _isSwitching = true;
    _notice = null;
    notifyListeners();
    try {
      final facility = await _repository.acceptInvitation(invitation.id);
      _replaceFacility(facility);
      _pendingInvitations = List.unmodifiable(
        _pendingInvitations.where((item) => item.id != invitation.id),
      );
      _selectedFacility = facility;
      await _saveSelection(facility.id);
      return true;
    } on FacilityException catch (error) {
      _notice = error.message;
      if (error.code == 'invitation_expired' ||
          error.code == 'invitation_unavailable' ||
          error.code == 'invitation_not_found') {
        _pendingInvitations = List.unmodifiable(
          _pendingInvitations.where((item) => item.id != invitation.id),
        );
      }
      return false;
    } catch (_) {
      _notice = 'The invitation could not be accepted. Try again.';
      return false;
    } finally {
      _isSwitching = false;
      notifyListeners();
    }
  }

  Future<void> addAndSelect(Facility facility) async {
    _replaceFacility(facility);
    _selectedFacility = facility;
    _notice = null;
    await _saveSelection(facility.id);
    notifyListeners();
  }

  void clearNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    notifyListeners();
  }

  Future<void> _loadFacilities({required bool useSavedSelection}) async {
    _isLoading = true;
    _loadError = null;
    _notice = null;
    notifyListeners();
    try {
      final loaded = await _repository.listFacilities();
      _facilities = List.unmodifiable(loaded);
      _pendingInvitations = List.unmodifiable(
        await _repository.listMyPendingInvitations(),
      );

      String? preferredId = _selectedFacility?.id;
      if (useSavedSelection) {
        preferredId = await _selectionStore.readSelectedFacilityId(_userId);
      }

      final preferred = _findById(preferredId);
      final previousWasRemoved = preferredId != null && preferred == null;
      _selectedFacility =
          preferred ?? (_facilities.isEmpty ? null : _facilities.first);

      if (_selectedFacility == null) {
        await _selectionStore.clearSelectedFacilityId(_userId);
      } else if (_selectedFacility!.id != preferredId) {
        await _saveSelection(_selectedFacility!.id);
      }

      if (previousWasRemoved) {
        _notice = _selectedFacility == null
            ? 'Your previously selected aquarium is no longer accessible.'
            : 'Your previously selected aquarium is no longer accessible. '
                  'Switched to ${_selectedFacility!.name}.';
      }
    } on FacilityException catch (error) {
      _loadError = error.message;
    } catch (_) {
      _loadError = 'Your aquariums could not be loaded.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _recoverFromInaccessibleFacility() async {
    final inaccessibleId = _selectedFacility?.id;
    try {
      final loaded = await _repository.listFacilities();
      _facilities = List.unmodifiable(loaded);
      _pendingInvitations = List.unmodifiable(
        await _repository.listMyPendingInvitations(),
      );
      final stillSelected = _findById(inaccessibleId);
      _selectedFacility =
          stillSelected ?? (_facilities.isEmpty ? null : _facilities.first);
      if (_selectedFacility == null) {
        await _selectionStore.clearSelectedFacilityId(_userId);
        _notice = 'That aquarium is no longer accessible.';
      } else {
        await _saveSelection(_selectedFacility!.id);
        _notice =
            'That aquarium is no longer accessible. '
            'Switched to ${_selectedFacility!.name}.';
      }
    } on FacilityException catch (error) {
      _notice = error.message;
    } catch (_) {
      _notice = 'That aquarium could not be opened. Try again.';
    }
  }

  Facility? _findById(String? id) {
    if (id == null) {
      return null;
    }
    for (final facility in _facilities) {
      if (facility.id == id) {
        return facility;
      }
    }
    return null;
  }

  void _replaceFacility(Facility facility) {
    final updated = [..._facilities];
    final index = updated.indexWhere((item) => item.id == facility.id);
    if (index == -1) {
      updated.add(facility);
    } else {
      updated[index] = facility;
    }
    _facilities = List.unmodifiable(updated);
  }

  Future<void> _saveSelection(String facilityId) async {
    await _selectionStore.saveSelectedFacilityId(
      userId: _userId,
      facilityId: facilityId,
    );
  }
}
