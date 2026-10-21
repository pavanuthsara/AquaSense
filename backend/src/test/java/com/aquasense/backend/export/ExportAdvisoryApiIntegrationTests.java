package com.aquasense.backend.export;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.concurrent.atomic.AtomicReference;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.export.client.ExportSimulator;
import com.aquasense.backend.export.client.ExportSimulatorException;
import com.aquasense.backend.export.repository.ExportAdvisoryRepository;
import com.aquasense.backend.facility.repository.FacilityInvitationRepository;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@Import(ExportAdvisoryApiIntegrationTests.FakeSimulatorConfig.class)
class ExportAdvisoryApiIntegrationTests {
    private static final String SHIPMENT = """
            {"label":"Dubai \\"rush\\" order","species":"guppy","fishMassG":0.3,"totalFish":1000,
             "waterL":0.4,"gasL":1.2,"durationH":36,"tempLowC":24,"tempHighC":28}""";

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
    private ExportAdvisoryRepository advisories;
    @Autowired
    private TokenService tokenService;
    @Autowired
    private FakeSimulator simulator;

    @BeforeEach
    @AfterEach
    void cleanDatabase() {
        advisories.deleteAll();
        invitations.deleteAll();
        memberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
        simulator.reset();
    }

    @Test
    void memberCanPlanAShipmentAndReadItBack() throws Exception {
        String token = token("export-owner", "owner@example.com");
        String facilityId = createFacility(token, "export-facility", "Export Reef");

        String json = mockMvc.perform(post("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(SHIPMENT))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.label", is("Dubai \"rush\" order")))
                .andExpect(jsonPath("$.request.species", is("guppy")))
                .andExpect(jsonPath("$.request.target_survival", is(0.95)))
                .andExpect(jsonPath("$.advisory.recommendation.fish_per_bag", is(48)))
                .andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(json, "$.id");

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].fishPerBag", is(48)))
                .andExpect(jsonPath("$[0].bagsNeeded", is(21)))
                .andExpect(jsonPath("$[0].survivalPct", is(96.3)))
                .andExpect(jsonPath("$[0].feasible", is(true)));

        mockMvc.perform(get("/api/v1/facilities/{facilityId}/export-advisories/{id}", facilityId, id)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.advisory.oxygen.explanation", is("O2 story")));
    }

    @Test
    void nonMembersCannotSeeOrCreatePlans() throws Exception {
        String owner = token("export-owner2", "owner2@example.com");
        String stranger = token("export-stranger", "stranger@example.com");
        String facilityId = createFacility(owner, "export-facility-2", "Private Reef");

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + stranger)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(SHIPMENT))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", is("facility_not_found")));
        mockMvc.perform(get("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + stranger))
                .andExpect(status().isNotFound());
    }

    @Test
    void invalidShipmentsAreRejectedBeforeCallingTheSimulator() throws Exception {
        String token = token("export-owner3", "owner3@example.com");
        String facilityId = createFacility(token, "export-facility-3", "Check Reef");

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"species\":\"Guppy; drop\",\"fishMassG\":0.3,\"waterL\":0.4,\"gasL\":1.2,"
                                + "\"durationH\":36,\"tempLowC\":24,\"tempHighC\":28}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(post("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"species\":\"guppy\",\"fishMassG\":0.3,\"waterL\":0.4,\"gasL\":1.2,"
                                + "\"durationH\":36,\"tempLowC\":30,\"tempHighC\":24}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", is("invalid_temperature_range")));
        org.junit.jupiter.api.Assertions.assertNull(simulator.lastRequest.get());
    }

    @Test
    void simulatorOutageIsReportedAsServiceUnavailable() throws Exception {
        String token = token("export-owner4", "owner4@example.com");
        String facilityId = createFacility(token, "export-facility-4", "Outage Reef");
        simulator.down = true;

        mockMvc.perform(post("/api/v1/facilities/{facilityId}/export-advisories", facilityId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(SHIPMENT))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code", is("export_simulator_unavailable")));
    }

    private String token(String subject, String email) {
        AppUser user = users.save(new AppUser(subject, email, "Exporter", null, Instant.now()));
        return tokenService.issue(user).accessToken();
    }

    private String createFacility(String token, String requestKey, String name) throws Exception {
        String json = mockMvc.perform(post("/api/v1/facilities")
                        .header("Authorization", "Bearer " + token)
                        .header("Idempotency-Key", requestKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"timeZone\":\"Asia/Colombo\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return JsonPath.read(json, "$.id");
    }

    static class FakeSimulator implements ExportSimulator {
        final AtomicReference<String> lastRequest = new AtomicReference<>();
        volatile boolean down;

        void reset() {
            lastRequest.set(null);
            down = false;
        }

        @Override
        public AdvisoryResult advise(String requestJson) {
            lastRequest.set(requestJson);
            if (down) {
                throw new ExportSimulatorException("down", false, null);
            }
            String json = "{\"feasible\":true,\"recommendation\":{\"fish_per_bag\":48,\"bags_needed\":21},"
                    + "\"oxygen\":{\"explanation\":\"O2 story\"}}";
            return new AdvisoryResult(json, true, 48, 21, 96.3, 95.2);
        }
    }

    @TestConfiguration
    static class FakeSimulatorConfig {
        @Bean
        @Primary
        FakeSimulator fakeExportSimulator() {
            return new FakeSimulator();
        }
    }
}
