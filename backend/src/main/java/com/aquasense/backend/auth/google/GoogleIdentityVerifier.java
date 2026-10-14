package com.aquasense.backend.auth.google;

public interface GoogleIdentityVerifier {
    GoogleIdentity verify(String idToken);
}
