package com.aquasense.backend.auth.google;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import com.aquasense.backend.auth.config.AuthProperties;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

class GoogleJwtIdentityVerifierTests {
    private final AuthProperties properties = new AuthProperties(
            "web-client.apps.googleusercontent.com",
            "unused-in-this-test",
            Duration.ofMinutes(15),
            Duration.ofDays(30),
            "aquasense-api",
            "aquasense-mobile");

    @Test
    void acceptsVerifiedGoogleClaimsForConfiguredAudience() {
        JwtDecoder decoder = mock(JwtDecoder.class);
        when(decoder.decode("valid")).thenReturn(googleJwt(
                "https://accounts.google.com",
                List.of(properties.googleClientId()),
                true));

        GoogleIdentity identity = new GoogleJwtIdentityVerifier(properties, decoder).verify("valid");

        assertThat(identity.subject()).isEqualTo("google-subject");
        assertThat(identity.email()).isEqualTo("owner@example.com");
        assertThat(identity.displayName()).isEqualTo("Aqua Owner");
    }

    @Test
    void rejectsWrongAudienceOrUnverifiedEmail() {
        JwtDecoder decoder = mock(JwtDecoder.class);
        when(decoder.decode("wrong-audience")).thenReturn(googleJwt(
                "https://accounts.google.com",
                List.of("another-client"),
                true));
        when(decoder.decode("unverified-email")).thenReturn(googleJwt(
                "https://accounts.google.com",
                List.of(properties.googleClientId()),
                false));
        GoogleJwtIdentityVerifier verifier = new GoogleJwtIdentityVerifier(properties, decoder);

        assertThatThrownBy(() -> verifier.verify("wrong-audience"))
                .isInstanceOf(AuthenticationFailureException.class);
        assertThatThrownBy(() -> verifier.verify("unverified-email"))
                .isInstanceOf(AuthenticationFailureException.class);
    }

    @Test
    void mapsExpiredOrInvalidGoogleTokenToAuthenticationFailure() {
        JwtDecoder decoder = mock(JwtDecoder.class);
        when(decoder.decode("expired")).thenThrow(new JwtException("expired"));

        assertThatThrownBy(() -> new GoogleJwtIdentityVerifier(properties, decoder).verify("expired"))
                .isInstanceOf(AuthenticationFailureException.class)
                .hasMessageContaining("invalid or expired");
    }

    private Jwt googleJwt(String issuer, List<String> audience, boolean emailVerified) {
        Instant now = Instant.now();
        return new Jwt(
                "token",
                now.minusSeconds(10),
                now.plusSeconds(300),
                Map.of("alg", "RS256"),
                Map.of(
                        "iss", issuer,
                        "sub", "google-subject",
                        "aud", audience,
                        "email", "OWNER@EXAMPLE.COM",
                        "email_verified", emailVerified,
                        "name", "Aqua Owner",
                        "picture", "https://example.com/photo.jpg"));
    }
}
