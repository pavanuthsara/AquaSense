package com.aquasense.backend.export.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Where the Python transit simulator (export_simulator/transit_sim/api.py) runs.
 *
 * @param baseUrl    e.g. http://localhost:8001
 * @param serviceKey shared secret sent as X-Service-Key (must match EXPORT_SIM_SERVICE_KEY on the Python side)
 * @param timeout    read timeout; an advisory takes a few seconds
 */
@ConfigurationProperties("aquasense.export-simulator")
public record ExportSimulatorProperties(String baseUrl, String serviceKey, Duration timeout) {
    public ExportSimulatorProperties {
        if (baseUrl == null || baseUrl.isBlank()) {
            baseUrl = "http://localhost:8001";
        }
        if (timeout == null) {
            timeout = Duration.ofSeconds(60);
        }
    }
}
