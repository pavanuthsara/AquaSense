package com.aquasense.backend.auth.web;

public class RegistrationConflictException extends RuntimeException {
    public RegistrationConflictException() {
        super("An account already uses this email. Sign in using your original login method.");
    }
}
