package com.aquasense.backend.facility.model;

public enum AppetiteCheckStatus {
    PENDING, CHECKING, COMPLETED, INSUFFICIENT_DATA, FAILED, TIMED_OUT;

    public boolean isActive() { return this == PENDING || this == CHECKING; }
}
