package com.aquasense.backend.facility;

import static org.hamcrest.Matchers.is;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import java.time.Instant;
import java.util.UUID;
import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.repository.AppetiteObservationRepository;
import com.aquasense.backend.facility.service.DeviceHealthService;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AppetiteCheckApiIntegrationTests {
    @Autowired MockMvc mvc;
    @Autowired AppUserRepository users;
    @Autowired TokenService tokens;
    @Autowired DeviceHealthService deviceHealth;
    @Autowired AppetiteObservationRepository observations;
    @Autowired JdbcTemplate jdbc;

    @Test
    void freshCheckIsDeliveredToAssignedProcessorAndDisplayedWithoutFeedingObservation() throws Exception {
        Setup s = setup(true);
        String id = request(s).andExpect(status().isAccepted()).andReturn().getResponse().getContentAsString();
        String checkId = JsonPath.read(id, "$.id");
        request(s).andExpect(jsonPath("$.id", is(checkId)));
        next(s).andExpect(status().isOk()).andExpect(jsonPath("$.id", is(checkId)))
                .andExpect(jsonPath("$.status", is("CHECKING")));
        result(s, checkId, completed("HIGH", Instant.now())).andExpect(status().isOk())
                .andExpect(jsonPath("$.appetiteResult", is("HIGH")));
        read(s, checkId).andExpect(status().isOk()).andExpect(jsonPath("$.status", is("COMPLETED")))
                .andExpect(jsonPath("$.confidence", is(0.875)));
        // A retry cannot change the already displayed result.
        result(s, checkId, completed("LOW", Instant.now())).andExpect(jsonPath("$.appetiteResult", is("HIGH")));
        next(s).andExpect(status().isNoContent());
        assertEquals(0, observations.findFirstByTank_IdOrderByObservedAtDescReceivedAtDesc(UUID.fromString(s.tank())).stream().count());
    }

    @Test
    void unavailableDataHasNoAppetiteLabelAndAnotherCheckCanBeRequested() throws Exception {
        Setup s = setup(true);
        String id = checkId(s);
        next(s).andExpect(status().isOk());
        result(s, id, "{\"status\":\"INSUFFICIENT_DATA\",\"message\":\"No fish tracked\"}")
                .andExpect(status().isOk()).andExpect(jsonPath("$.status", is("INSUFFICIENT_DATA")))
                .andExpect(jsonPath("$.appetiteResult").doesNotExist());
        request(s).andExpect(jsonPath("$.status", is("PENDING")));
    }

    @Test
    void noProcessorAndAnonymousAndUnrelatedUsersAreRejected() throws Exception {
        Setup s = setup(false);
        request(s).andExpect(status().isConflict()).andExpect(jsonPath("$.code", is("edge_processor_missing")));
        mvc.perform(post(path(s))).andExpect(status().isUnauthorized());
        AppUser outsider = users.save(new AppUser(UUID.randomUUID().toString(), "outside@example.com", "Outside", null, Instant.now()));
        mvc.perform(post(path(s)).header("Authorization", "Bearer " + tokens.issue(outsider).accessToken()))
                .andExpect(status().isNotFound());
    }

    @Test
    void cameraCredentialsAndAnotherTanksProcessorCannotSubmitResults() throws Exception {
        Setup s = setup(true);
        String id = checkId(s);
        var camera = deviceHealth.provision(s.user(), UUID.fromString(s.facility()), UUID.fromString(s.tank()), DeviceType.CAMERA);
        mvc.perform(get("/api/v1/device-appetite-checks/next")
                        .header("X-Device-Id", camera.device().getId()).header("X-Device-Token", camera.heartbeatToken()))
                .andExpect(status().isForbidden());
        Setup other = setup(true);
        next(other).andExpect(status().isNoContent());
        result(other, id, completed("HIGH", Instant.now())).andExpect(status().isNotFound());
        mvc.perform(get("/api/v1/device-appetite-checks/next")
                        .header("X-Device-Id", s.device()).header("X-Device-Token", "wrong"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void pendingAndOldPredictionsAreRejectedAndExpiredChecksCannotBeRevived() throws Exception {
        Setup s = setup(true);
        String id = checkId(s);
        result(s, id, completed("HIGH", Instant.now())).andExpect(status().isConflict());
        next(s).andExpect(status().isOk());
        result(s, id, completed("HIGH", Instant.now().minusSeconds(120))).andExpect(status().isBadRequest());
        result(s, id, "{\"status\":\"PENDING\"}").andExpect(status().isBadRequest());
        jdbc.update("update appetite_checks set expires_at = ? where id = ?", Instant.now().minusSeconds(1), UUID.fromString(id));
        // Clear first-level cache so the externally modified deadline is reloaded.
        entityManager.clear();
        read(s, id).andExpect(status().isOk()).andExpect(jsonPath("$.status", is("TIMED_OUT")));
        result(s, id, completed("HIGH", Instant.now())).andExpect(jsonPath("$.status", is("TIMED_OUT")));
    }

    @Autowired jakarta.persistence.EntityManager entityManager;

    private String checkId(Setup s) throws Exception {
        return JsonPath.read(request(s).andExpect(status().isAccepted()).andReturn().getResponse().getContentAsString(), "$.id");
    }

    private ResultActions request(Setup s) throws Exception {
        return mvc.perform(post(path(s)).header("Authorization", s.bearer()));
    }

    private ResultActions read(Setup s, String id) throws Exception {
        return mvc.perform(get(path(s) + "/" + id).header("Authorization", s.bearer()));
    }

    private ResultActions next(Setup s) throws Exception {
        return mvc.perform(get("/api/v1/device-appetite-checks/next")
                .header("X-Device-Id", s.device()).header("X-Device-Token", s.deviceToken()));
    }

    private ResultActions result(Setup s, String id, String body) throws Exception {
        return mvc.perform(post("/api/v1/device-appetite-checks/" + id + "/result")
                .header("X-Device-Id", s.device()).header("X-Device-Token", s.deviceToken())
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private String path(Setup s) {
        return "/api/v1/facilities/" + s.facility() + "/tanks/" + s.tank() + "/appetite-checks";
    }

    private String completed(String label, Instant now) {
        return """
                {"status":"COMPLETED","appetiteResult":"%s","confidence":0.8750,
                "modelVersion":"random_forest_live_pre-v1","observedAt":"%s"}
                """.formatted(label, now);
    }

    private Setup setup(boolean provision) throws Exception {
        String unique = UUID.randomUUID().toString();
        AppUser user = users.save(new AppUser(unique, unique + "@example.com", "Owner", null, Instant.now()));
        String bearer = "Bearer " + tokens.issue(user).accessToken();
        String facility = JsonPath.read(mvc.perform(post("/api/v1/facilities")
                .header("Authorization", bearer).header("Idempotency-Key", unique)
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Test Reef\",\"timeZone\":\"Asia/Colombo\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id");
        String tank = JsonPath.read(mvc.perform(post("/api/v1/facilities/" + facility + "/tanks")
                .header("Authorization", bearer).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Tank\",\"code\":\"T1\",\"expectedGuppyCount\":10,\"tags\":[],\"automationEnabled\":false,\"notes\":\"\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString(), "$.id");
        if (!provision) return new Setup(user.getId(), bearer, facility, tank, null, null);
        var device = deviceHealth.provision(user.getId(), UUID.fromString(facility), UUID.fromString(tank), DeviceType.EDGE_PROCESSOR);
        return new Setup(user.getId(), bearer, facility, tank, device.device().getId(), device.heartbeatToken());
    }

    private record Setup(UUID user, String bearer, String facility, String tank, UUID device, String deviceToken) {}
}
