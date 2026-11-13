package com.aquasense.backend.disease;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.disease.repository.DiseaseCheckRepository;
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
class DiseaseCheckApiIntegrationTests {
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
    private DiseaseCheckRepository checks;

    @Autowired
    private TokenService tokenService;

    @BeforeEach
    void cleanDatabase() {
        checks.deleteAll();
        memberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
    }

    @Test
    void diseaseCheckEndpointsRequireAuthentication() throws Exception {
        mockMvc.perform(get("/api/v1/facilities/{id}/disease-checks", "00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void memberCanRecordAndListChecksNewestFirst() throws Exception {
        String token = accessToken("dis-owner-1", "dis1@example.com");
        String facilityId = facility(token, "Guppy House");
        Instant earlier = Instant.now().minus(2, ChronoUnit.HOURS).truncatedTo(ChronoUnit.MILLIS);
        Instant later = Instant.now().minus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.MILLIS);

        record(token, facilityId, "check-1", body("healthy", 0.97, false, "Tank A", earlier), 201)
                .andExpect(jsonPath("$.predictedLabel", is("healthy")))
                .andExpect(jsonPath("$.checkedByName", is("Disease Tester")));
        record(token, facilityId, "check-2", body("white_spot", 0.99, false, null, later), 201);

        mockMvc.perform(get("/api/v1/facilities/{id}/disease-checks", facilityId)
                        .header("Authorization", bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].predictedLabel", is("white_spot")))
                .andExpect(jsonPath("$[1].predictedLabel", is("healthy")))
                .andExpect(jsonPath("$[1].tankLabel", is("Tank A")));

        mockMvc.perform(get("/api/v1/facilities/{id}/disease-checks", facilityId)
                        .param("limit", "1")
                        .header("Authorization", bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void repeatedRequestReturnsSameCheckWithoutDuplicate() throws Exception {
        String token = accessToken("dis-owner-2", "dis2@example.com");
        String facilityId = facility(token, "Retry Reef");
        String content = body("white_spot", 0.55, true, null, Instant.now().minusSeconds(30));

        String first = record(token, facilityId, "same-key", content, 201)
                .andReturn().getResponse().getContentAsString();
        String repeated = record(token, facilityId, "same-key", content, 200)
                .andReturn().getResponse().getContentAsString();

        assertThat((String) JsonPath.read(repeated, "$.id")).isEqualTo(JsonPath.read(first, "$.id"));
        assertThat(checks.count()).isEqualTo(1);
    }

    @Test
    void reusingKeyForDifferentResultIsRejected() throws Exception {
        String token = accessToken("dis-owner-3", "dis3@example.com");
        String facilityId = facility(token, "Conflict Reef");
        Instant checkedAt = Instant.now().minusSeconds(30);
        record(token, facilityId, "key-x", body("healthy", 0.9, false, null, checkedAt), 201);

        record(token, facilityId, "key-x", body("white_spot", 0.9, false, null, checkedAt), 409)
                .andExpect(jsonPath("$.code", is("idempotency_conflict")));
    }

    @Test
    void invalidResultsAreRejected() throws Exception {
        String token = accessToken("dis-owner-4", "dis4@example.com");
        String facilityId = facility(token, "Validation Reef");
        Instant now = Instant.now();

        record(token, facilityId, "bad-1", body("healthy", 1.5, false, null, now), 400)
                .andExpect(jsonPath("$.code", is("invalid_request")));
        record(token, facilityId, "bad-2", body("White Spot!", 0.9, false, null, now), 400)
                .andExpect(jsonPath("$.code", is("invalid_request")));
        record(token, facilityId, "bad-3", body("healthy", 0.9, false, null, now.plus(1, ChronoUnit.DAYS)), 400)
                .andExpect(jsonPath("$.code", is("invalid_checked_at")));
        mockMvc.perform(get("/api/v1/facilities/{id}/disease-checks", facilityId)
                        .param("limit", "500")
                        .header("Authorization", bearer(token)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("invalid_limit")));
        assertThat(checks.count()).isZero();
    }

    @Test
    void otherUsersCannotReadOrWriteAnotherAquariumsChecks() throws Exception {
        String owner = accessToken("dis-owner-5", "dis5@example.com");
        String stranger = accessToken("dis-stranger", "stranger@example.com");
        String facilityId = facility(owner, "Private Reef");
        record(owner, facilityId, "private-1", body("healthy", 0.9, false, null, Instant.now()), 201);

        mockMvc.perform(get("/api/v1/facilities/{id}/disease-checks", facilityId)
                        .header("Authorization", bearer(stranger)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("facility_not_found")));
        record(stranger, facilityId, "sneaky", body("white_spot", 0.9, false, null, Instant.now()), 404)
                .andExpect(jsonPath("$.code", is("facility_not_found")));
        assertThat(checks.count()).isEqualTo(1);
    }

    private org.springframework.test.web.servlet.ResultActions record(
            String token, String facilityId, String key, String content, int expectedStatus) throws Exception {
        return mockMvc.perform(post("/api/v1/facilities/{id}/disease-checks", facilityId)
                        .header("Authorization", bearer(token))
                        .header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(content))
                .andExpect(status().is(expectedStatus));
    }

    private static String body(String label, double confidence, boolean uncertain, String tank, Instant checkedAt) {
        return "{\"predictedLabel\":\"" + label + "\","
                + "\"confidence\":" + confidence + ","
                + "\"uncertain\":" + uncertain + ","
                + "\"modelVersion\":\"guppy-white-spot-2026-10-16\","
                + (tank == null ? "" : "\"tankLabel\":\"" + tank + "\",")
                + "\"checkedAt\":\"" + checkedAt + "\"}";
    }

    private String facility(String token, String name) throws Exception {
        String created = mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", bearer(token))
                        .header("Idempotency-Key", "facility-" + name)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"timeZone\":\"Asia/Colombo\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(created, "$.id");
    }

    private String accessToken(String googleSubject, String email) {
        AppUser user = users.save(new AppUser(googleSubject, email, "Disease Tester", null, Instant.now()));
        return tokenService.issue(user).accessToken();
    }

    private static String bearer(String token) {
        return "Bearer " + token;
    }
}
