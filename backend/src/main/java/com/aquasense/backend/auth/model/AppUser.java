package com.aquasense.backend.auth.model;

import java.time.Instant;
import java.util.UUID;
import java.util.Locale;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "app_users")
public class AppUser {
    @Id
    private UUID id;

    @Column(name = "google_subject", unique = true)
    private String googleSubject;

    @Column(name = "password_hash")
    private String passwordHash;

    @Column(nullable = false, unique = true, length = 320)
    private String email;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "photo_url", length = 2048)
    private String photoUrl;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "last_login_at", nullable = false)
    private Instant lastLoginAt;

    protected AppUser() {
    }

    public AppUser(String googleSubject, String email, String displayName, String photoUrl, Instant now) {
        this.id = UUID.randomUUID();
        this.googleSubject = googleSubject;
        updateProfile(email, displayName, photoUrl, now);
        this.createdAt = now;
    }

    public void updateProfile(String email, String displayName, String photoUrl, Instant now) {
        this.email = email.trim().toLowerCase(Locale.ROOT);
        this.displayName = displayName;
        this.photoUrl = photoUrl;
        this.updatedAt = now;
        this.lastLoginAt = now;
    }

    public static AppUser withPassword(String email, String displayName, String passwordHash, Instant now) {
        AppUser user = new AppUser(null, email, displayName, null, now);
        user.passwordHash = passwordHash;
        return user;
    }

    public void recordLogin(Instant now) {
        this.lastLoginAt = now;
    }

    // Only Google currently proves email ownership. Password registration does not.
    public boolean hasVerifiedEmail() { return googleSubject != null; }
    public String getPasswordHash() { return passwordHash; }

    public UUID getId() { return id; }
    public String getGoogleSubject() { return googleSubject; }
    public String getEmail() { return email; }
    public String getDisplayName() { return displayName; }
    public String getPhotoUrl() { return photoUrl; }
}
