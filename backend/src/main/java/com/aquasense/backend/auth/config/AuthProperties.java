package com.aquasense.backend.auth.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("aquasense.auth")
public record AuthProperties(
        String googleClientId,
        String jwtSecret,
        Duration accessTokenTtl,
        Duration refreshTokenTtl,
        String issuer,
        String audience) {
}
