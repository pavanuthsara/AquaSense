package com.aquasense.backend.facility;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Set;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.repository.FacilityInvitationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.TankGroupRepository;
import com.aquasense.backend.facility.repository.TankRepository;
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
class TankApiIntegrationTests {
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
    private TankRepository tanks;
    @Autowired
    private TokenService tokenService;

    @BeforeEach
    void cleanDatabase() {
        tanks.deleteAll();
        groups.deleteAll();
        invitations.deleteAll();
        memberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
    }

    @Test
    void ownerCanCreateMoveEditAndArchiveTankWhileCountsStayCorrect() throws Exception {
        TestUser owner = user("tank-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "tank-facility", "Blue Reef");
        String nurseryId = createGroup(owner.token(), facilityId, "Nursery");
        String growOutId = createGroup(owner.token(), facilityId, "Grow Out");

        String tankId = createTank(owner.token(), facilityId, """
                {"name":"Nursery 1","code":"N-001","expectedGuppyCount":80,
                 "groupId":"%s","tags":["Breeding","priority"],
                 "automationEnabled":true,"notes":"Observe daily"}
                """.formatted(nurseryId), 201);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.name == 'Nursery')].tankCount", is(java.util.List.of(1))));

        mockMvc.perform(patch("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"Juvenile 1","code":"N-001","expectedGuppyCount":75,
                                 "groupId":"%s","tags":["priority","juvenile"],
                                 "automationEnabled":false,"notes":"Moved"}
                                """.formatted(growOutId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groupName", is("Grow Out")))
                .andExpect(jsonPath("$.status", is("PAUSED")))
                .andExpect(jsonPath("$.tags", is(java.util.List.of("juvenile", "priority"))));

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/tanks/{tankId}/archive", facilityId, tankId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status", is("ARCHIVED")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].tankCount", is(java.util.List.of(0, 0))));
    }

    @Test
    void workerCanSearchAndInspectButCannotManageTanks() throws Exception {
        TestUser owner = user("worker-owner", "owner@example.com", "Owner");
        TestUser worker = user("worker-user", "worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "worker-facility", "Worker Reef");
        String tankId = createTank(owner.token(), facilityId, basicTank("Display Tank", "D-001"), 201);
        String invitationId = invite(owner.token(), facilityId, worker.user().getEmail());
        accept(worker.token(), invitationId);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks", facilityId)
                        .header("Authorization", bearer(worker.token()))
                        .queryParam("query", "D-001"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(1)));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(worker.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tank.name", is("Display Tank")));
        createTank(worker.token(), facilityId, basicTank("Blocked", "B-001"), 403);
    }

    @Test
    void paginationSearchStatusTagAndUnassignedFiltersHandleOneThousandTanks() throws Exception {
        TestUser owner = user("scale-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "scale-facility", "Scale Reef");
        Facility facility = facilities.findById(UUID.fromString(facilityId)).orElseThrow();
        Instant now = Instant.now();
        var seeded = new ArrayList<Tank>(1000);
        for (int index = 0; index < 1000; index++) {
            String code = "T-%04d".formatted(index);
            seeded.add(new Tank(
                    facility,
                    null,
                    "Tank %04d".formatted(index),
                    code,
                    code.toLowerCase(),
                    50 + (index % 20),
                    index % 2 == 0 ? Set.of("breeding") : Set.of("display"),
                    index % 3 != 0,
                    null,
                    now));
        }
        tanks.saveAll(seeded);
        tanks.flush();

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks", facilityId)
                        .header("Authorization", bearer(owner.token()))
                        .queryParam("page", "0")
                        .queryParam("size", "50"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(50)))
                .andExpect(jsonPath("$.totalItems", is(1000)))
                .andExpect(jsonPath("$.totalPages", is(20)));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks", facilityId)
                        .header("Authorization", bearer(owner.token()))
                        .queryParam("query", "T-0999"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(1)))
                .andExpect(jsonPath("$.items[0].code", is("T-0999")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks", facilityId)
                        .header("Authorization", bearer(owner.token()))
                        .queryParam("status", "PAUSED")
                        .queryParam("tag", "breeding")
                        .queryParam("unassigned", "true")
                        .queryParam("size", "100"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalItems", is(500)));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tank-tags", facilityId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", is(java.util.List.of("breeding", "display"))));
    }

    @Test
    void tankCodesStayUniqueWithinFacilityAndIdentifiersRemainScoped() throws Exception {
        TestUser firstOwner = user("code-one", "one@example.com", "One");
        TestUser secondOwner = user("code-two", "two@example.com", "Two");
        String firstFacility = createFacility(firstOwner.token(), "code-facility-one", "First");
        String secondFacility = createFacility(secondOwner.token(), "code-facility-two", "Second");
        String tankId = createTank(firstOwner.token(), firstFacility, basicTank("One", "A-001"), 201);

        createTank(firstOwner.token(), firstFacility, basicTank("Duplicate", "a-001"), 409);
        createTank(secondOwner.token(), secondFacility, basicTank("Allowed", "A-001"), 201);
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", secondFacility, tankId)
                        .header("Authorization", bearer(secondOwner.token())))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("tank_not_found")));
    }

    @Test
    void tankDetailUsesExplicitNoDataStatesUntilMonitoringIsConfigured() throws Exception {
        TestUser owner = user("detail-owner", "owner@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "detail-facility", "Detail Reef");
        String tankId = createTank(owner.token(), facilityId, basicTank("Detail Tank", "DT-1"), 201);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.observationState", is("NO_DATA")))
                .andExpect(jsonPath("$.deviceStatus", is("NOT_CONFIGURED")))
                .andExpect(jsonPath("$.scheduleMode", is("INHERITED")))
                .andExpect(jsonPath("$.feedingTimes", hasSize(0)))
                .andExpect(jsonPath("$.lastFeedingAt").doesNotExist())
                .andExpect(jsonPath("$.nextFeedingAt").doesNotExist())
                .andExpect(jsonPath("$.recentActivity[0].type", is("TANK_CREATED")));
    }

    @Test
    void ownerCanReplaceInheritedScheduleWithTankOverrideAndWorkerCannotChangeIt() throws Exception {
        TestUser owner = user("schedule-owner", "schedule-owner@example.com", "Owner");
        TestUser worker = user("schedule-worker", "schedule-worker@example.com", "Worker");
        String facilityId = createFacility(owner.token(), "schedule-facility", "Schedule Reef");
        String groupId = createGroup(owner.token(), facilityId, "Nursery");
        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/feeding-schedule",
                        facilityId, groupId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"times":["08:00","16:00"],"automationEnabled":true}
                                """))
                .andExpect(status().isOk());
        String tankId = createTank(owner.token(), facilityId, """
                {"name":"Nursery 1","code":"NS-1","expectedGuppyCount":80,
                 "groupId":"%s","tags":[],"automationEnabled":true,"notes":""}
                """.formatted(groupId), 201);
        String invitationId = invite(owner.token(), facilityId, worker.user().getEmail());
        accept(worker.token(), invitationId);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.scheduleMode", is("INHERITED")))
                .andExpect(jsonPath("$.feedingTimes", is(java.util.List.of("08:00", "16:00"))))
                .andExpect(jsonPath("$.nextFeedingAt").isNotEmpty());

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule",
                        facilityId, tankId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"OVERRIDE","times":["09:30","18:15"]}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.scheduleMode", is("OVERRIDE")))
                .andExpect(jsonPath("$.feedingTimes", is(java.util.List.of("09:30", "18:15"))))
                .andExpect(jsonPath("$.nextFeedingAt").isNotEmpty());

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule",
                        facilityId, tankId)
                        .header("Authorization", bearer(worker.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"INHERITED","times":[]}
                                """))
                .andExpect(status().isForbidden());

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule",
                        facilityId, tankId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"INHERITED","times":[]}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.scheduleMode", is("INHERITED")))
                .andExpect(jsonPath("$.feedingTimes", is(java.util.List.of("08:00", "16:00"))));

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tank-groups/{groupId}/feeding-schedule",
                        facilityId, groupId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"times":["10:00"],"automationEnabled":true}
                                """))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.feedingTimes", is(java.util.List.of("10:00"))));
    }

    @Test
    void unassignedTankIsPausedUntilItHasACompleteOverride() throws Exception {
        TestUser owner = user("unassigned-owner", "unassigned@example.com", "Owner");
        String facilityId = createFacility(owner.token(), "unassigned-facility", "Safe Reef");
        String tankId = createTank(owner.token(), facilityId, basicTank("Unassigned", "U-1"), 201);

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/tanks/{tankId}", facilityId, tankId)
                        .header("Authorization", bearer(owner.token())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tank.status", is("PAUSED")))
                .andExpect(jsonPath("$.scheduleMode", is("INHERITED")))
                .andExpect(jsonPath("$.feedingTimes", hasSize(0)))
                .andExpect(jsonPath("$.nextFeedingAt").doesNotExist());

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule",
                        facilityId, tankId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"OVERRIDE","times":[]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("override_schedule_empty")));

        mockMvc.perform(put("/api/v1/facilities/{facilityId}/tanks/{tankId}/feeding-schedule",
                        facilityId, tankId)
                        .header("Authorization", bearer(owner.token()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"OVERRIDE","times":["07:00"]}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.scheduleMode", is("OVERRIDE")))
                .andExpect(jsonPath("$.feedingTimes", is(java.util.List.of("07:00"))));
    }

    private String basicTank(String name, String code) {
        return """
                {"name":"%s","code":"%s","expectedGuppyCount":60,"groupId":null,
                 "tags":["display"],"automationEnabled":true,"notes":""}
                """.formatted(name, code);
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

    private String createGroup(String token, String facilityId, String name) throws Exception {
        String json = mockMvc.perform(post("/api/v1/facilities/{facilityId}/tank-groups", facilityId)
                        .header("Authorization", bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(json, "$.id");
    }

    private String createTank(String token, String facilityId, String body, int expectedStatus) throws Exception {
        var result = mockMvc.perform(post("/api/v1/facilities/{facilityId}/tanks", facilityId)
                        .header("Authorization", bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
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

    private TestUser user(String subject, String email, String name) {
        AppUser user = users.save(new AppUser(subject, email, name, null, Instant.now()));
        return new TestUser(user, tokenService.issue(user).accessToken());
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }

    private record TestUser(AppUser user, String token) {
    }
}
