package com.aquasense.backend.auth.google;

public record GoogleIdentity(String subject, String email, String displayName, String photoUrl) {
}
