package com.aquasense.backend.auth.web;

import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.service.AuthenticationService;
import com.aquasense.backend.auth.service.AuthenticationService.AuthenticatedSession;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthenticationService authenticationService;

    public AuthController(AuthenticationService authenticationService) {
        this.authenticationService = authenticationService;
    }

    @PostMapping("/google/exchange")
    SessionResponse exchange(@Valid @RequestBody GoogleExchangeRequest request) {
        return SessionResponse.from(authenticationService.exchangeGoogleToken(request.idToken()));
    }

    @PostMapping("/refresh")
    SessionResponse refresh(@Valid @RequestBody RefreshRequest request) {
        return SessionResponse.from(authenticationService.refresh(request.refreshToken()));
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void logout(@Valid @RequestBody RefreshRequest request) {
        authenticationService.logout(request.refreshToken());
    }

    @GetMapping("/me")
    UserResponse me(@AuthenticationPrincipal Jwt jwt) {
        return UserResponse.from(authenticationService.getUser(UUID.fromString(jwt.getSubject())));
    }

    public record GoogleExchangeRequest(@NotBlank String idToken) {
    }

    public record RefreshRequest(@NotBlank String refreshToken) {
    }

    public record SessionResponse(
            String accessToken,
            String refreshToken,
            String tokenType,
            long expiresInSeconds,
            UserResponse user) {
        static SessionResponse from(AuthenticatedSession session) {
            return new SessionResponse(
                    session.tokens().accessToken(),
                    session.tokens().refreshToken(),
                    "Bearer",
                    session.tokens().expiresInSeconds(),
                    UserResponse.from(session.user()));
        }
    }

    public record UserResponse(UUID id, String email, String displayName, String photoUrl) {
        static UserResponse from(AppUser user) {
            return new UserResponse(user.getId(), user.getEmail(), user.getDisplayName(), user.getPhotoUrl());
        }
    }
}
