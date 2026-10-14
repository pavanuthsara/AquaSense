package com.aquasense.backend.auth.service;

import java.time.Instant;
import java.util.UUID;

import com.aquasense.backend.auth.google.GoogleIdentity;
import com.aquasense.backend.auth.google.GoogleIdentityVerifier;
import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.model.RefreshToken;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthenticationService {
    private final GoogleIdentityVerifier googleIdentityVerifier;
    private final AppUserRepository users;
    private final TokenService tokens;

    public AuthenticationService(
            GoogleIdentityVerifier googleIdentityVerifier,
            AppUserRepository users,
            TokenService tokens) {
        this.googleIdentityVerifier = googleIdentityVerifier;
        this.users = users;
        this.tokens = tokens;
    }

    @Transactional
    public AuthenticatedSession exchangeGoogleToken(String idToken) {
        GoogleIdentity identity = googleIdentityVerifier.verify(idToken);
        if (users.existsByEmailIgnoreCaseAndGoogleSubjectNot(identity.email(), identity.subject())) {
            throw new AuthenticationFailureException("That verified email is linked to another Google identity");
        }
        Instant now = Instant.now();
        AppUser user = users.findByGoogleSubject(identity.subject())
                .map(existing -> {
                    existing.updateProfile(identity.email(), identity.displayName(), identity.photoUrl(), now);
                    return existing;
                })
                .orElseGet(() -> new AppUser(
                        identity.subject(), identity.email(), identity.displayName(), identity.photoUrl(), now));
        users.save(user);
        return new AuthenticatedSession(user, tokens.issue(user));
    }

    @Transactional
    public AuthenticatedSession refresh(String refreshToken) {
        RefreshToken current = tokens.requireUsableRefreshToken(refreshToken);
        AppUser user = current.getUser();
        tokens.revoke(current);
        return new AuthenticatedSession(user, tokens.issue(user));
    }

    @Transactional
    public void logout(String refreshToken) {
        tokens.revokeIfPresent(refreshToken);
    }

    @Transactional(readOnly = true)
    public AppUser getUser(UUID userId) {
        return users.findById(userId)
                .orElseThrow(() -> new AuthenticationFailureException("The authenticated user no longer exists"));
    }

    public record AuthenticatedSession(AppUser user, TokenService.IssuedTokens tokens) {
    }
}
