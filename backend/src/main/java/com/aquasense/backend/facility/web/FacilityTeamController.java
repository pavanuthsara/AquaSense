package com.aquasense.backend.facility.web;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityInvitation;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.InvitationStatus;
import com.aquasense.backend.facility.service.FacilityTeamService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class FacilityTeamController {
    private final FacilityTeamService teamService;

    public FacilityTeamController(FacilityTeamService teamService) {
        this.teamService = teamService;
    }

    @GetMapping("/facilities/{facilityId}/members")
    List<MemberResponse> listMembers(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return teamService.listMembers(userId(jwt), facilityId).stream()
                .map(MemberResponse::from)
                .toList();
    }

    @GetMapping("/facilities/{facilityId}/invitations")
    List<InvitationResponse> listInvitations(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId) {
        return teamService.listFacilityInvitations(userId(jwt), facilityId).stream()
                .map(InvitationResponse::from)
                .toList();
    }

    @PostMapping("/facilities/{facilityId}/invitations")
    @ResponseStatus(HttpStatus.CREATED)
    InvitationResponse invite(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @Valid @RequestBody InviteWorkerRequest request) {
        return InvitationResponse.from(teamService.invite(userId(jwt), facilityId, request.email()));
    }

    @DeleteMapping("/facilities/{facilityId}/invitations/{invitationId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void revokeInvitation(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID invitationId) {
        teamService.revokeInvitation(userId(jwt), facilityId, invitationId);
    }

    @DeleteMapping("/facilities/{facilityId}/members/{membershipId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void removeWorker(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @PathVariable UUID membershipId) {
        teamService.removeWorker(userId(jwt), facilityId, membershipId);
    }

    @GetMapping("/invitations/me")
    List<InvitationResponse> listMyInvitations(@AuthenticationPrincipal Jwt jwt) {
        return teamService.listMyPendingInvitations(userId(jwt)).stream()
                .map(InvitationResponse::from)
                .toList();
    }

    @PostMapping("/invitations/{invitationId}/accept")
    FacilityAccessResponse accept(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID invitationId) {
        return FacilityAccessResponse.from(teamService.accept(userId(jwt), invitationId));
    }

    private UUID userId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }

    public record InviteWorkerRequest(
            @NotBlank @Email @Size(max = 320) String email) {
    }

    public record MemberResponse(
            UUID id,
            UUID userId,
            String email,
            String displayName,
            FacilityRole role,
            Instant joinedAt) {
        static MemberResponse from(FacilityMembership membership) {
            AppUser user = membership.getUser();
            return new MemberResponse(
                    membership.getId(),
                    user.getId(),
                    user.getEmail(),
                    user.getDisplayName(),
                    membership.getRole(),
                    membership.getJoinedAt());
        }
    }

    public record InvitationResponse(
            UUID id,
            UUID facilityId,
            String facilityName,
            String email,
            InvitationStatus status,
            Instant expiresAt,
            Instant createdAt) {
        static InvitationResponse from(FacilityInvitation invitation) {
            Facility facility = invitation.getFacility();
            return new InvitationResponse(
                    invitation.getId(),
                    facility.getId(),
                    facility.getName(),
                    invitation.getEmail(),
                    invitation.getStatus(),
                    invitation.getExpiresAt(),
                    invitation.getCreatedAt());
        }
    }

    public record FacilityAccessResponse(
            UUID id,
            String name,
            String timeZone,
            FacilityRole role,
            Instant createdAt) {
        static FacilityAccessResponse from(FacilityMembership membership) {
            Facility facility = membership.getFacility();
            return new FacilityAccessResponse(
                    facility.getId(),
                    facility.getName(),
                    facility.getTimeZone(),
                    membership.getRole(),
                    facility.getCreatedAt());
        }
    }
}
