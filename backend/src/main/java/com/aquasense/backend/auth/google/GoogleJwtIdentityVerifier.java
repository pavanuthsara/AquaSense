package com.aquasense.backend.auth.google;

import java.util.List;

import com.aquasense.backend.auth.config.AuthProperties;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;

@Component
public class GoogleJwtIdentityVerifier implements GoogleIdentityVerifier {
    private static final String GOOGLE_JWKS_URI = "https://www.googleapis.com/oauth2/v3/certs";
    private static final List<String> GOOGLE_ISSUERS =
            List.of("accounts.google.com", "https://accounts.google.com");

    private final JwtDecoder decoder;
    private final AuthProperties properties;

    @Autowired
    public GoogleJwtIdentityVerifier(AuthProperties properties) {
        this(properties, NimbusJwtDecoder.withJwkSetUri(GOOGLE_JWKS_URI).build());
    }

    GoogleJwtIdentityVerifier(AuthProperties properties, JwtDecoder decoder) {
        this.properties = properties;
        this.decoder = decoder;
    }

    @Override
    public GoogleIdentity verify(String idToken) {
        if (properties.googleClientId() == null || properties.googleClientId().isBlank()) {
            throw new IllegalStateException("AQUASENSE_GOOGLE_CLIENT_ID must be configured");
        }

        final Jwt jwt;
        try {
            jwt = decoder.decode(idToken);
        } catch (JwtException exception) {
            throw new AuthenticationFailureException("The Google identity token is invalid or expired");
        }

        String issuer = jwt.getIssuer() == null ? null : jwt.getIssuer().toString();
        Boolean emailVerified = jwt.getClaim("email_verified");
        String email = jwt.getClaimAsString("email");
        if (!GOOGLE_ISSUERS.contains(issuer)
                || !jwt.getAudience().contains(properties.googleClientId())
                || !Boolean.TRUE.equals(emailVerified)
                || jwt.getSubject() == null
                || jwt.getSubject().isBlank()
                || email == null
                || email.isBlank()) {
            throw new AuthenticationFailureException("The Google identity token could not be verified");
        }

        String displayName = jwt.getClaimAsString("name");
        if (displayName == null || displayName.isBlank()) {
            displayName = email.substring(0, email.indexOf('@'));
        }
        return new GoogleIdentity(
                jwt.getSubject(),
                email.toLowerCase(),
                displayName,
                jwt.getClaimAsString("picture"));
    }
}
