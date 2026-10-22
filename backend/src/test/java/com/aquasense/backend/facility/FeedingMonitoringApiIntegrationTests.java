package com.aquasense.backend.facility;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.service.TokenService;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.model.FeedingOutcome;
import com.aquasense.backend.facility.model.FeedingSession;
import com.aquasense.backend.facility.model.Tank;
import com.aquasense.backend.facility.model.TankGroup;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.aquasense.backend.facility.repository.FeedingSessionRepository;
import com.aquasense.backend.facility.repository.TankGroupRepository;
import com.aquasense.backend.facility.repository.TankRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class FeedingMonitoringApiIntegrationTests {
    private static final Instant BASE = Instant.parse("2026-01-01T12:00:00Z");

    @Autowired private MockMvc mvc;
    @Autowired private AppUserRepository users;
    @Autowired private FacilityRepository facilities;
    @Autowired private FacilityMembershipRepository memberships;
    @Autowired private TankGroupRepository groups;
    @Autowired private TankRepository tanks;
    @Autowired private FeedingSessionRepository sessions;
    @Autowired private TokenService tokens;

    private AppUser owner;
    private Facility facility;
    private String bearer;

    @BeforeEach
    void setUp() {
        String identity = UUID.randomUUID().toString();
        owner = users.save(new AppUser(identity, identity + "@example.com", "History Owner", null, BASE));
        facility = facility("History Reef");
        bearer = "Bearer " + tokens.issue(owner).accessToken();
    }

    @Test
    void emptyDashboardAndHistoryWorkWithoutOptionalFilters() throws Exception {
        mvc.perform(get("/api/v1/facilities/{id}/feeding-dashboard", facility.getId())
                        .header("Authorization", bearer))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recentSessions", hasSize(0)));
        mvc.perform(history()).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)))
                .andExpect(jsonPath("$.nextCursor").doesNotExist());
    }

    @Test
    void unfilteredHistoryIncludesUngroupedTanksAndExcludesOtherFacilities() throws Exception {
        TankGroup group = groups.save(new TankGroup(facility, "Nursery", "nursery", BASE));
        session(tank(facility, group, "Grouped"), BASE, FeedingOutcome.BLOCKED_AUTOMATION);
        Tank ungrouped = tank(facility, null, "Ungrouped");
        FeedingSession latest = session(ungrouped, BASE.plusSeconds(1), FeedingOutcome.SKIPPED_LOW_APPETITE);
        session(tank(facility("Other Reef"), null, "Foreign"), BASE.plusSeconds(2), FeedingOutcome.DELIVERED);

        mvc.perform(history()).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(2)))
                .andExpect(jsonPath("$.items[0].id", is(latest.getId().toString())))
                .andExpect(jsonPath("$.items[0].groupId").doesNotExist());
        mvc.perform(get("/api/v1/facilities/{id}/feeding-dashboard", facility.getId())
                        .header("Authorization", bearer))
                .andExpect(status().isOk()).andExpect(jsonPath("$.recentSessions", hasSize(2)));
        mvc.perform(get("/api/v1/facilities/{id}/tanks/{tankId}/feeding-history", facility.getId(), ungrouped.getId())
                        .header("Authorization", bearer))
                .andExpect(status().isOk()).andExpect(jsonPath("$.items", hasSize(1)));
    }

    @Test
    void dateBoundsAreOptionalInclusiveFromAndExclusiveTo() throws Exception {
        Tank tank = tank(facility, null, "Bounds");
        session(tank, BASE.minusSeconds(1), FeedingOutcome.BLOCKED_AUTOMATION);
        FeedingSession atFrom = session(tank, BASE, FeedingOutcome.BLOCKED_AUTOMATION);
        session(tank, BASE.plusSeconds(1), FeedingOutcome.BLOCKED_AUTOMATION);

        mvc.perform(history().param("from", BASE.toString())).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(2)));
        mvc.perform(history().param("to", BASE.toString())).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(1)));
        mvc.perform(history().param("from", BASE.toString()).param("to", BASE.plusSeconds(1).toString()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.items", hasSize(1)))
                .andExpect(jsonPath("$.items[0].id", is(atFrom.getId().toString())));
    }

    @Test
    void optionalTankGroupSourceAndOutcomeFiltersComposeWithinFacility() throws Exception {
        TankGroup group = groups.save(new TankGroup(facility, "Nursery", "nursery", BASE));
        Tank grouped = tank(facility, group, "Grouped");
        FeedingSession match = session(grouped, BASE, FeedingOutcome.BLOCKED_AUTOMATION);
        session(grouped, BASE.plusSeconds(1), FeedingOutcome.SKIPPED_LOW_APPETITE);
        session(tank(facility, null, "Ungrouped"), BASE, FeedingOutcome.BLOCKED_AUTOMATION);

        mvc.perform(history().param("groupId", group.getId().toString())).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(2)));
        mvc.perform(history().param("tankId", grouped.getId().toString())
                        .param("groupId", group.getId().toString()).param("source", "SCHEDULED")
                        .param("outcome", "BLOCKED_AUTOMATION").param("from", BASE.toString())
                        .param("to", BASE.plusSeconds(5).toString()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.items", hasSize(1)))
                .andExpect(jsonPath("$.items[0].id", is(match.getId().toString())));
        mvc.perform(history().param("source", "MANUAL")).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)));
        mvc.perform(history().param("outcome", "DELIVERED")).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)));
        Facility foreign = facility("Other Reef");
        TankGroup foreignGroup = groups.save(new TankGroup(foreign, "Foreign", "foreign", BASE));
        Tank foreignTank = tank(foreign, foreignGroup, "Foreign");
        session(foreignTank, BASE, FeedingOutcome.BLOCKED_AUTOMATION);
        mvc.perform(history().param("tankId", foreignTank.getId().toString())).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)));
        mvc.perform(history().param("groupId", foreignGroup.getId().toString())).andExpect(status().isOk())
                .andExpect(jsonPath("$.items", hasSize(0)));
    }

    @Test
    void cursorUsesUuidTieBreakerWithoutRepeatsOrSkippedRows() throws Exception {
        Tank first = tank(facility, null, "First");
        List<FeedingSession> rows = new ArrayList<>();
        rows.add(session(first, BASE, FeedingOutcome.BLOCKED_AUTOMATION));
        rows.add(session(tank(facility, null, "Second"), BASE, FeedingOutcome.BLOCKED_AUTOMATION));
        rows.add(session(tank(facility, null, "Third"), BASE, FeedingOutcome.BLOCKED_AUTOMATION));
        rows.add(session(first, BASE.minusSeconds(1), FeedingOutcome.BLOCKED_AUTOMATION));
        rows.sort(Comparator.comparing(FeedingSession::getScheduledFor).reversed()
                .thenComparing(item -> item.getId().toString(), Comparator.reverseOrder()));

        List<String> actualIds = new ArrayList<>();
        String cursor = null;
        for (int page = 0; page < 2; page++) {
            var request = history().param("size", "2");
            if (cursor != null) request.param("cursor", cursor);
            String response = mvc.perform(request).andExpect(status().isOk())
                    .andExpect(jsonPath("$.items", hasSize(2)))
                    .andReturn().getResponse().getContentAsString();
            actualIds.addAll(JsonPath.<List<String>>read(response, "$.items[*].id"));
            cursor = JsonPath.read(response, "$.nextCursor");
            if (page == 0) assertThat(cursor).isNotBlank();
        }
        assertThat(cursor).isNull();
        assertThat(actualIds).containsExactlyElementsOf(rows.stream().map(item -> item.getId().toString()).toList());
    }

    @Test
    void accessAndInvalidInputChecksRemainEnforced() throws Exception {
        String identity = UUID.randomUUID().toString();
        AppUser outsider = users.save(new AppUser(identity, identity + "@example.com", "Outsider", null, BASE));
        String outsiderBearer = "Bearer " + tokens.issue(outsider).accessToken();
        mvc.perform(get("/api/v1/facilities/{id}/feeding-history", facility.getId())
                        .header("Authorization", outsiderBearer))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/v1/facilities/{id}/feeding-dashboard", facility.getId())
                        .header("Authorization", outsiderBearer)).andExpect(status().isNotFound());
        mvc.perform(history().param("from", BASE.toString()).param("to", BASE.toString()))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("invalid_date_range")));
        mvc.perform(history().param("cursor", "invalid-cursor"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code", is("invalid_cursor")));
    }

    private MockHttpServletRequestBuilder history() {
        return get("/api/v1/facilities/{id}/feeding-history", facility.getId()).header("Authorization", bearer);
    }

    private Facility facility(String name) {
        Facility created = facilities.save(new Facility(owner, name, "UTC", UUID.randomUUID().toString(), BASE));
        memberships.save(new FacilityMembership(created, owner, FacilityRole.OWNER, BASE));
        return created;
    }

    private Tank tank(Facility facility, TankGroup group, String name) {
        return tanks.save(new Tank(facility, group, name, name, name, 10, Set.of(), false, null, BASE));
    }

    private FeedingSession session(Tank tank, Instant time, FeedingOutcome outcome) {
        FeedingSession session = new FeedingSession(tank, time, BASE);
        session.stop(outcome, null, null, BASE);
        return sessions.saveAndFlush(session);
    }
}
