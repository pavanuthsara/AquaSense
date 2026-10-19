package com.aquasense.backend.facility;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.facility.repository.FacilityInvitationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.TankGroupRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class TankGroupApiIntegrationTests {
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
    private TankGroupRepository groups;

    @Autowired
    private TokenService tokenService;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        groups.deleteAll();
        invitations.deleteAll();
        memberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
    }

    @Test
    void ownerCanCreateRenameListAndArchiveEmptyGroups() throws Exception {
        TestUser owner = user("groups-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "groups-facility", "Blue Reef");
        String groupId = createGroup(owner.token(), facilityId, "  Nursery  ", 201);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name", is("Nursery")))
                .andExpect(jsonPath("$[0].tankCount", is(0)))
                .andExpect(jsonPath("$[0].archived", is(false)));

        mockMvc.perform(patch("/api/v1/facilities/{facilityId}/tank-groups/{groupId}", facilityId, groupId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Juvenile Tanks\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name", is("Juvenile Tanks")));

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive", facilityId, groupId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.archived", is(true)))
                .andExpect(jsonPath("$.archivedAt").isNotEmpty());
    }

    @Test
    void activeGroupNamesAreUniqueButArchivedNamesCanBeReused() throws Exception {
        TestUser owner = user("names-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "names-facility", "Name Reef");
        String groupId = createGroup(owner.token(), facilityId, "Nursery", 201);

        createGroup(owner.token(), facilityId, " nursery ", 409);
        mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive", facilityId, groupId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk());
        createGroup(owner.token(), facilityId, "nursery", 201);
    }

    @Test
    void workerCanViewGroupsButCannotManageThem() throws Exception {
        TestUser owner = user("role-owner", "owner@example.com", "Owner");
        TestUser worker = user("role-worker", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "role-facility", "Role Reef");
        String groupId = createGroup(owner.token(), facilityId, "Grow Out", 201);
        String invitationId = invite(owner.token(), facilityId, worker.user().getEmail());
        accept(worker.token(), invitationId);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
        createGroup(worker.token(), facilityId, "Worker Group", 403);
        mockMvc.perform(patch("/api/v1/facilities/{facilityId}/tank-groups/{groupId}", facilityId, groupId)
                        .header("Authorization", bearer(worker.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Changed\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", is("owner_required")));
        mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive", facilityId, groupId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", is("owner_required")));
    }

    @Test
    void groupsAreFacilityScopedWithoutLeakingTheirIdentifiers() throws Exception {
        TestUser firstOwner = user("scope-owner-one", "one@example.com", "Owner One");
        TestUser secondOwner = user("scope-owner-two", "two@example.com", "Owner Two");
        String firstFacility = createFacility(firstOwner.token(), "scope-one", "First Reef");
        String secondFacility = createFacility(secondOwner.token(), "scope-two", "Second Reef");
        String groupId = createGroup(firstOwner.token(), firstFacility, "Private Group", 201);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", firstFacility)
                        .header("Authorization", bearer(secondOwner.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("facility_not_found")));
        mockMvc.perform(patch("/api/v1/facilities/{facilityId}/tank-groups/{groupId}", secondFacility, groupId)
                        .header("Authorization", bearer(secondOwner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Stolen\"}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("tank_group_not_found")));
    }

    @Test
    void groupWithTanksCannotBeArchived() throws Exception {
        TestUser owner = user("count-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "count-facility", "Count Reef");
        String groupId = createGroup(owner.token(), facilityId, "Occupied", 201);
        jdbcTemplate.update("UPDATE tank_groups SET tank_count = 2 WHERE id = ?", UUID.fromString(groupId));

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/archive", facilityId, groupId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("group_not_empty")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].tankCount", is(2)))
                .andExpect(jsonPath("$[0].archived", is(false)));
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

    private String createGroup(String token, String facilityId, String name, int expectedStatus) throws Exception {
        var result = mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\"}"))
                .andExpect(status().is(expectedStatus));
        if (expectedStatus >= 200 && expectedStatus < 300) {
            return JsonPath.read(result.andReturn().getResponse().getContentAsString(), "$.id");
        }
        return null;
    }

    private String invite(String token, String facilityId, String email) throws Exception {
        String json = mockMvc.perform(post("/api/v1/facilities/{facilityId}/invitations", facilityId)
                        .header("Authorization", bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(json, "$.id");
    }

    private void accept(String token, String invitationId) throws Exception {
        mockMvc.perform(post("/api/v1/invitations/{invitationId}/accept", invitationId)
                        .header("Authorization", bearer(token)))
                .andExpect(status().isOk());
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
