package com.aquasense.backend.facility;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityInvitation;
import com.aquasense.backend.facility.model.InvitationStatus;
import com.aquasense.backend.facility.repository.FacilityInvitationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class FacilityTeamApiIntegrationTests {
    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AppUserRepository users;

    @Autowired
    private RefreshTokenRepository refreshTokens;

    @Autowired
    private FacilityRepository facilities;

    @Autowired
    private FacilityMembershipRepository memberships;

    @Autowired
    private FacilityInvitationRepository invitations;

    @Autowired
    private TokenService tokenService;

    @BeforeEach
    void cleanDatabase() {
        invitations.deleteAll();
        memberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
    }

    @Test
    void matchingVerifiedEmailCanAcceptInvitationIdempotently() throws Exception {
        TestUser owner = user("team-owner", "owner@example.com", "Owner");
        TestUser worker = user("team-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "team-facility", "Blue Reef");
        String invitationId = invite(owner.token(), facilityId, "WORKER@example.com", 201);

        mockMvc.perform(get("/api/v1/invitations/me").header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].facilityName", is("Blue Reef")))
                .andExpect(jsonPath("$[0].email", is("worker@example.com")));

        accept(worker.token(), invitationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is(facilityId)))
                .andExpect(jsonPath("$.role", is("WORKER")));
        accept(worker.token(), invitationId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is(facilityId)));

        mockMvc.perform(get("/api/v1/facilities").header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].role", is("WORKER")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/members", facilityId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)));
    }

    @Test
    void invitationIsHiddenFromAndCannotBeAcceptedByDifferentEmail() throws Exception {
        TestUser owner = user("hidden-owner", "owner@example.com", "Owner");
        TestUser invited = user("hidden-worker", "worker@example.com", "Worker");
        TestUser stranger = user("hidden-stranger", "stranger@example.com", "Stranger");
        String facilityId = createFacility(owner.token(), "hidden-facility", "Private Reef");
        String invitationId = invite(owner.token(), facilityId, invited.user().getEmail(), 201);

        mockMvc.perform(get("/api/v1/invitations/me").header("Authorization", bearer(stranger.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        accept(stranger.token(), invitationId)
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("invitation_not_found")));
    }

    @Test
    void duplicateInvitationsAndExistingMembersAreRejected() throws Exception {
        TestUser owner = user("duplicate-owner", "owner@example.com", "Owner");
        TestUser worker = user("duplicate-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "duplicate-facility", "Guppy House");
        String invitationId = invite(owner.token(), facilityId, worker.user().getEmail(), 201);

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"worker@example.com\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("invitation_already_pending")));

        accept(worker.token(), invitationId).andExpect(status().isOk());
        mockMvc.perform(post("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"worker@example.com\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("already_a_member")));
    }

    @Test
    void workerCannotUseOwnerOnlyTeamActions() throws Exception {
        TestUser owner = user("permission-owner", "owner@example.com", "Owner");
        TestUser worker = user("permission-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "permission-facility", "Role Reef");
        String invitationId = invite(owner.token(), facilityId, worker.user().getEmail(), 201);
        accept(worker.token(), invitationId).andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(worker.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"new@example.com\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", is("owner_required")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", is("owner_required")));
    }

    @Test
    void ownerCanRevokeInvitationAndRemoveWorkerAccess() throws Exception {
        TestUser owner = user("revoke-owner", "owner@example.com", "Owner");
        TestUser worker = user("revoke-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "revoke-facility", "Access Reef");
        String revokedInvitation = invite(owner.token(), facilityId, worker.user().getEmail(), 201);

        mockMvc.perform(delete("/api/v1/facilities/{facilityId}/invitations/{invitationId}",
                        facilityId, revokedInvitation)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isNoContent());
        accept(worker.token(), revokedInvitation)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.code", is("invitation_unavailable")));

        String activeInvitation = invite(owner.token(), facilityId, worker.user().getEmail(), 201);
        accept(worker.token(), activeInvitation).andExpect(status().isOk());
        String membersJson = mockMvc.perform(get("/api/v1/facilities/{facilityId}/members", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        List<String> workerMembershipIds = JsonPath.read(membersJson, "$[?(@.role == 'WORKER')].id");
        String workerMembershipId = workerMembershipIds.getFirst();

        mockMvc.perform(delete("/api/v1/facilities/{facilityId}/members/{membershipId}",
                        facilityId, workerMembershipId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/facilities/{facilityId}", facilityId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isNotFound());
    }

    @Test
    void expiredInvitationCannotBeAcceptedAndIsRemovedFromPendingList() throws Exception {
        TestUser owner = user("expiry-owner", "owner@example.com", "Owner");
        TestUser worker = user("expiry-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "expiry-facility", "Old Reef");
        Facility facility = facilities.findById(UUID.fromString(facilityId)).orElseThrow();
        Instant createdAt = Instant.now().minus(Duration.ofDays(8));
        FacilityInvitation invitation = invitations.save(new FacilityInvitation(
                facility,
                owner.user(),
                worker.user().getEmail(),
                createdAt,
                createdAt.plus(Duration.ofDays(7))));

        accept(worker.token(), invitation.getId().toString())
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.code", is("invitation_expired")));
        mockMvc.perform(get("/api/v1/invitations/me").header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        org.assertj.core.api.Assertions.assertThat(invitations.findById(invitation.getId()).orElseThrow().getStatus())
                .isEqualTo(InvitationStatus.EXPIRED);
    }

    private String createFacility(String token, String requestKey, String name) throws Exception {
        String json = mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", bearer(token))
                        .header("Idempotency-Key", requestKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"timeZone\":\"Asia/Colombo\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(json, "$.id");
    }

    private String invite(String token, String facilityId, String email, int expectedStatus) throws Exception {
        String json = mockMvc.perform(post("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\"}"))
                .andExpect(status().is(expectedStatus))
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(json, "$.id");
    }

    private org.springframework.test.web.servlet.ResultActions accept(String token, String invitationId)
            throws Exception {
        return mockMvc.perform(post("/api/v1/invitations/{invitationId}/accept", invitationId)
                .header("Authorization", bearer(token)));
    }

    private TestUser user(String googleSubject, String email, String displayName) {
        Instant now = Instant.now();
        AppUser user = users.save(new AppUser(googleSubject, email, displayName, null, now));
        return new TestUser(user, tokenService.issue(user).accessToken());
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }

    private record TestUser(AppUser user, String token) {
    }
}
