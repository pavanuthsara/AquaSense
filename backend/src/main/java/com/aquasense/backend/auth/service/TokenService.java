package com.aquasense.backend.auth.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;

import com.aquasense.backend.auth.config.AuthProperties;
import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.model.RefreshToken;
import com.aquasense.backend.auth.repository.RefreshTokenRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;

@Service
public class TokenService {
    private final JwtEncoder jwtEncoder;
    private final RefreshTokenRepository refreshTokens;
    private final AuthProperties properties;
    private final SecureRandom random = new SecureRandom();
    private final Clock clock = Clock.systemUTC();

    public TokenService(JwtEncoder jwtEncoder, RefreshTokenRepository refreshTokens, AuthProperties properties) {
        this.jwtEncoder = jwtEncoder;
        this.refreshTokens = refreshTokens;
        this.properties = properties;
    }

    public IssuedTokens issue(AppUser user) {
        Instant now = clock.instant();
        Instant accessExpiry = now.plus(properties.accessTokenTtl());
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(properties.issuer())
                .audience(java.util.List.of(properties.audience()))
                .subject(user.getId().toString())
                .issuedAt(now)
                .expiresAt(accessExpiry)
                .claim("email", user.getEmail())
                .build();
        String accessToken = jwtEncoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();

        String rawRefreshToken = newRefreshToken();
        refreshTokens.save(new RefreshToken(
                user,
                hash(rawRefreshToken),
                now,
                now.plus(properties.refreshTokenTtl())));
        return new IssuedTokens(accessToken, rawRefreshToken, accessExpiry, properties.accessTokenTtl().toSeconds());
    }

    public RefreshToken requireUsableRefreshToken(String rawToken) {
        RefreshToken token = refreshTokens.findByTokenHash(hash(rawToken))
                .orElseThrow(() -> new AuthenticationFailureException("The refresh token is invalid"));
        if (!token.isUsableAt(clock.instant())) {
            throw new AuthenticationFailureException("The refresh token is expired or revoked");
        }
        return token;
    }

    public void revoke(RefreshToken token) {
        token.revoke(clock.instant());
        refreshTokens.save(token);
    }

    public void revokeIfPresent(String rawToken) {
        refreshTokens.findByTokenHash(hash(rawToken)).ifPresent(this::revoke);
    }

    private String newRefreshToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String hash(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    public record IssuedTokens(
            String accessToken,
            String refreshToken,
            Instant accessTokenExpiresAt,
            long expiresInSeconds) {
    }
}
