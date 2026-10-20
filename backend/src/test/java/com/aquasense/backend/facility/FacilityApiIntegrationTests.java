package com.aquasense.backend.facility;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
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
class FacilityApiIntegrationTests {
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
    void facilityEndpointsRequireAuthentication() throws Exception {
        mockMvc.perform(get("/api/v1/facilities"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void ownerCanCreateListAndSelectFirstFacility() throws Exception {
        String accessToken = accessToken("owner-1", "owner@example.com");

        String created = create(accessToken, "request-1", "  Blue Reef  ", "Asia/Colombo", 201);
        String facilityId = JsonPath.read(created, "$.id");

        mockMvc.perform(get("/api/v1/facilities").header("Authorization", bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name", is("Blue Reef")))
                .andExpect(jsonPath("$[0].timeZone", is("Asia/Colombo")))
                .andExpect(jsonPath("$[0].role", is("OWNER")));

        mockMvc.perform(get("/api/v1/facilities/{id}", facilityId)
                        .header("Authorization", bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id", is(facilityId)))
                .andExpect(jsonPath("$.role", is("OWNER")));
    }

    @Test
    void repeatedCreationRequestReturnsSameFacilityWithoutDuplicates() throws Exception {
        String accessToken = accessToken("owner-2", "owner2@example.com");

        String first = create(accessToken, "stable-request", "Guppy House", "UTC", 201);
        String repeated = create(accessToken, "stable-request", "Guppy House", "UTC", 200);

        org.assertj.core.api.Assertions.assertThat((String) JsonPath.read(repeated, "$.id"))
                .isEqualTo((String) JsonPath.read(first, "$.id"));
        org.assertj.core.api.Assertions.assertThat(facilities.count()).isEqualTo(1);
        org.assertj.core.api.Assertions.assertThat(memberships.count()).isEqualTo(1);
    }

    @Test
    void reusingCreationKeyWithDifferentDetailsIsRejected() throws Exception {
        String accessToken = accessToken("owner-3", "owner3@example.com");
        create(accessToken, "same-request", "First Aquarium", "UTC", 201);

        mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", bearer(accessToken))
                        .header("Idempotency-Key", "same-request")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Different Aquarium\",\"timeZone\":\"UTC\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", is("idempotency_conflict")));
    }

    @Test
    void invalidTimeZoneIsRejected() throws Exception {
        String accessToken = accessToken("owner-4", "owner4@example.com");

        mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", bearer(accessToken))
                        .header("Idempotency-Key", "bad-zone")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Blue Reef\",\"timeZone\":\"Not/AZone\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("invalid_time_zone")));
    }

    @Test
    void userCannotSelectAnotherOwnersFacility() throws Exception {
        String firstOwner = accessToken("owner-5", "owner5@example.com");
        String secondOwner = accessToken("owner-6", "owner6@example.com");
        String created = create(firstOwner, "private-facility", "Private Reef", "UTC", 201);
        String facilityId = JsonPath.read(created, "$.id");

        mockMvc.perform(get("/api/v1/facilities/{id}", facilityId)
                        .header("Authorization", bearer(secondOwner)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("facility_not_found")));
    }

    @Test
    void ownerCanListMultipleFacilitiesWithoutSeeingAnotherOwnersFacility() throws Exception {
        String firstOwner = accessToken("multi-owner", "multi@example.com");
        String secondOwner = accessToken("other-owner", "other@example.com");

        create(firstOwner, "multi-1", "Blue Reef", "Asia/Colombo", 201);
        create(firstOwner, "multi-2", "Guppy House", "UTC", 201);
        create(secondOwner, "other-1", "Private Hatchery", "UTC", 201);

        mockMvc.perform(get("/api/v1/facilities").header("Authorization", bearer(firstOwner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].name", is("Blue Reef")))
                .andExpect(jsonPath("$[1].name", is("Guppy House")));
    }

    @Test
    void authenticatedUserCanLoadSupportedTimeZones() throws Exception {
        String accessToken = accessToken("owner-7", "owner7@example.com");

        mockMvc.perform(get("/api/v1/facilities/timezones")
                        .header("Authorization", bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasItem("Asia/Colombo")))
                .andExpect(jsonPath("$", hasItem("UTC")));
    }

    private String create(
            String accessToken,
            String requestKey,
            String name,
            String timeZone,
            int expectedStatus) throws Exception {
        return mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", bearer(accessToken))
                        .header("Idempotency-Key", requestKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"timeZone\":\"" + timeZone + "\"}"))
                .andExpect(status().is(expectedStatus))
                .andExpect(jsonPath("$.role", is("OWNER")))
                .andReturn().getResponse().getContentAsString();
    }

    private String accessToken(String googleSubject, String email) {
        Instant now = Instant.now();
        AppUser user = users.save(new AppUser(googleSubject, email, "Facility Owner", null, now));
        return tokenService.issue(user).accessToken();
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }
}
