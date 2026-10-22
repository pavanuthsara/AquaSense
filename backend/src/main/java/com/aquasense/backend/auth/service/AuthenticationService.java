package com.aquasense.backend.auth.service;

import java.time.Instant;
import java.util.UUID;
import java.util.Locale;
import java.util.Objects;

import com.aquasense.backend.auth.google.GoogleIdentity;
import com.aquasense.backend.auth.google.GoogleIdentityVerifier;
import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.model.RefreshToken;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import com.aquasense.backend.auth.web.RegistrationConflictException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthenticationService {
    private final GoogleIdentityVerifier googleIdentityVerifier;
    private final AppUserRepository users;
    private final TokenService tokens;
    private final PasswordEncoder passwords;
    private final String dummyPasswordHash;

    public AuthenticationService(
            GoogleIdentityVerifier googleIdentityVerifier,
            AppUserRepository users,
            TokenService tokens,
            PasswordEncoder passwords) {
        this.googleIdentityVerifier = googleIdentityVerifier;
        this.users = users;
        this.tokens = tokens;
        this.passwords = passwords;
        this.dummyPasswordHash = passwords.encode(UUID.randomUUID().toString());
    }

    @Transactional
    public AuthenticatedSession exchangeGoogleToken(String idToken) {
        GoogleIdentity identity = googleIdentityVerifier.verify(idToken);
        if (users.findByEmailIgnoreCase(identity.email())
                .filter(existing -> !Objects.equals(existing.getGoogleSubject(), identity.subject())).isPresent()) {
            throw new AuthenticationFailureException(
                    "An account already uses this email. Sign in using your original login method.");
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
    public AuthenticatedSession register(String email, String displayName, String password) {
        String normalizedEmail = email.trim().toLowerCase(Locale.ROOT);
        if (users.findByEmailIgnoreCase(normalizedEmail).isPresent()) {
            throw new RegistrationConflictException();
        }
        AppUser user = AppUser.withPassword(
                normalizedEmail, displayName.trim(), passwords.encode(password), Instant.now());
        try {
            users.saveAndFlush(user);
        } catch (DataIntegrityViolationException exception) {
            // Includes a competing registration that won the unique-email constraint.
            throw new RegistrationConflictException();
        }
        return new AuthenticatedSession(user, tokens.issue(user));
    }

    @Transactional
    public AuthenticatedSession login(String email, String password) {
        AppUser user = users.findByEmailIgnoreCase(email.trim().toLowerCase(Locale.ROOT)).orElse(null);
        String hash = user == null || user.getPasswordHash() == null
                ? dummyPasswordHash : user.getPasswordHash();
        boolean matches = passwords.matches(password, hash);
        if (!matches || user == null || user.getPasswordHash() == null) {
            throw new AuthenticationFailureException("Email or password is incorrect.");
        }
        user.recordLogin(Instant.now());
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
