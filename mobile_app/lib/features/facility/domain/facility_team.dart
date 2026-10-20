import 'facility.dart';

enum FacilityInvitationStatus { pending, accepted, revoked, expired }

class FacilityMember {
  const FacilityMember({
    required this.id,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  final String id;
  final String userId;
  final String email;
  final String displayName;
  final FacilityRole role;
  final DateTime joinedAt;
}

class FacilityInvitation {
  const FacilityInvitation({
    required this.id,
    required this.facilityId,
    required this.facilityName,
    required this.email,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String facilityId;
  final String facilityName;
  final String email;
  final FacilityInvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;

  FacilityInvitation copyWith({FacilityInvitationStatus? status}) {
    return FacilityInvitation(
      id: id,
      facilityId: facilityId,
      facilityName: facilityName,
      email: email,
      status: status ?? this.status,
      expiresAt: expiresAt,
      createdAt: createdAt,
    );
  }
}
