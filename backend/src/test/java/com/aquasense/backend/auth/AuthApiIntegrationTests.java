package com.aquasense.backend.auth;

import static org.hamcrest.Matchers.is;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;

import com.aquasense.backend.auth.config.AuthProperties;
import com.aquasense.backend.auth.google.GoogleIdentity;
import com.aquasense.backend.auth.google.GoogleIdentityVerifier;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import com.aquasense.backend.facility.repository.FacilityMembershipRepository;
import com.aquasense.backend.facility.repository.FacilityRepository;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class AuthApiIntegrationTests {
    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AppUserRepository users;

    @Autowired
    private RefreshTokenRepository refreshTokens;

    @Autowired
    private FacilityMembershipRepository facilityMemberships;

    @Autowired
    private FacilityRepository facilities;

    @Autowired
    private JwtEncoder jwtEncoder;

    @Autowired
    private AuthProperties properties;

    @MockitoBean
    private GoogleIdentityVerifier googleIdentityVerifier;

    @BeforeEach
    void cleanDatabase() {
        facilityMemberships.deleteAll();
        facilities.deleteAll();
        refreshTokens.deleteAll();
        users.deleteAll();
    }

    @Test
    void exchangesGoogleIdentityAndCreatesLocalUser() throws Exception {
        when(googleIdentityVerifier.verify("valid-google-token")).thenReturn(identity("Aqua Owner"));

        mockMvc.perform(post("/api/v1/auth/google/exchange")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"idToken\":\"valid-google-token\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tokenType", is("Bearer")))
                .andExpect(jsonPath("$.expiresInSeconds", is(900)))
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.refreshToken").isNotEmpty())
                .andExpect(jsonPath("$.user.email", is("owner@example.com")))
                .andExpect(jsonPath("$.user.displayName", is("Aqua Owner")));

        org.assertj.core.api.Assertions.assertThat(users.count()).isEqualTo(1);
    }

    @Test
    void updatesExistingUserForSameGoogleSubject() throws Exception {
        when(googleIdentityVerifier.verify("first")).thenReturn(identity("First Name"));
        when(googleIdentityVerifier.verify("second")).thenReturn(identity("Updated Name"));

        exchange("first");
        mockMvc.perform(post("/api/v1/auth/google/exchange")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"idToken\":\"second\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.displayName", is("Updated Name")));

        org.assertj.core.api.Assertions.assertThat(users.count()).isEqualTo(1);
    }

    @Test
    void rejectsInvalidGoogleIdentity() throws Exception {
        when(googleIdentityVerifier.verify("invalid"))
                .thenThrow(new AuthenticationFailureException("Invalid Google token"));

        mockMvc.perform(post("/api/v1/auth/google/exchange")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"idToken\":\"invalid\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", is("authentication_failed")));
    }

    @Test
    void refreshRotatesTokenAndRejectsReplay() throws Exception {
        String initial = exchange("initial");
        String refreshToken = JsonPath.read(initial, "$.refreshToken");

        String rotated = mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(refreshRequest(refreshToken)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        org.assertj.core.api.Assertions.assertThat((String) JsonPath.read(rotated, "$.refreshToken"))
                .isNotEqualTo(refreshToken);

        mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(refreshRequest(refreshToken)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void meRequiresValidAccessToken() throws Exception {
        mockMvc.perform(get("/api/v1/auth/me"))
                .andExpect(status().isUnauthorized());

        String response = exchange("for-me");
        String accessToken = JsonPath.read(response, "$.accessToken");
        mockMvc.perform(get("/api/v1/auth/me")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email", is("owner@example.com")));
    }

    @Test
    void logoutRevokesRefreshToken() throws Exception {
        String response = exchange("logout");
        String refreshToken = JsonPath.read(response, "$.refreshToken");

        mockMvc.perform(post("/api/v1/auth/logout")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(refreshRequest(refreshToken)))
                .andExpect(status().isNoContent());

        mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(refreshRequest(refreshToken)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void rejectsExpiredAccessToken() throws Exception {
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(properties.issuer())
                .audience(List.of(properties.audience()))
                .subject("00000000-0000-0000-0000-000000000000")
                .issuedAt(now.minusSeconds(120))
                .expiresAt(now.minusSeconds(60))
                .build();
        String expiredToken = jwtEncoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();

        mockMvc.perform(get("/api/v1/auth/me")
                        .header("Authorization", "Bearer " + expiredToken))
                .andExpect(status().isUnauthorized());
    }

    private String exchange(String idToken) throws Exception {
        when(googleIdentityVerifier.verify(idToken)).thenReturn(identity("Aqua Owner"));
        return mockMvc.perform(post("/api/v1/auth/google/exchange")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"idToken\":\"" + idToken + "\"}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
    }

    private GoogleIdentity identity(String name) {
        return new GoogleIdentity("google-subject-123", "owner@example.com", name, "https://example.com/photo.jpg");
    }

    private String refreshRequest(String refreshToken) {
        return "{\"refreshToken\":\"" + refreshToken + "\"}";
    }
}
