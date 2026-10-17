package com.aquasense.backend.facility.service;

import org.springframework.http.HttpStatus;

public class FacilityException extends RuntimeException {
    private final HttpStatus status;
    private final String code;

    public FacilityException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public HttpStatus getStatus() { return status; }
    public String getCode() { return code; }
}
