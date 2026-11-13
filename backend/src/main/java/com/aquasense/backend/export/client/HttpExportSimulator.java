package com.aquasense.backend.export.client;

import java.time.Duration;

import com.aquasense.backend.export.config.ExportSimulatorProperties;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

public class HttpExportSimulator implements ExportSimulator {
    private final RestClient client;

    public HttpExportSimulator(ExportSimulatorProperties properties) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(5));
        factory.setReadTimeout(properties.timeout());
        RestClient.Builder builder = RestClient.builder()
                .baseUrl(properties.baseUrl())
                .requestFactory(factory);
        if (properties.serviceKey() != null && !properties.serviceKey().isBlank()) {
            builder.defaultHeader("X-Service-Key", properties.serviceKey());
        }
        this.client = builder.build();
    }

    @Override
    public AdvisoryResult advise(String requestJson) {
        try {
            ResponseEntity<String> response = client.post()
                    .uri("/v1/advisory")
                    .contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON)
                    .body(requestJson)
                    .retrieve()
                    .toEntity(String.class);
            HttpHeaders headers = response.getHeaders();
            String body = response.getBody();
            if (body == null || body.isBlank()) {
                throw new ExportSimulatorException("The transit simulator returned no advisory", false, null);
            }
            return new AdvisoryResult(
                    body,
                    Boolean.parseBoolean(headers.getFirst("X-Advisory-Feasible")),
                    Boolean.parseBoolean(headers.getFirst("X-Advisory-Meets-Target")),
                    integer(headers.getFirst("X-Advisory-Fish-Per-Bag")),
                    integer(headers.getFirst("X-Advisory-Bags-Needed")),
                    decimal(headers.getFirst("X-Advisory-Survival-Pct")),
                    decimal(headers.getFirst("X-Advisory-Worst-Survival-Pct")));
        } catch (RestClientResponseException exception) {
            int status = exception.getStatusCode().value();
            boolean invalid = status == 422 || status == 400;
            throw new ExportSimulatorException(
                    invalid ? "The simulator rejected the shipment details" : "The transit simulator failed",
                    invalid,
                    exception);
        } catch (RestClientException exception) {
            throw new ExportSimulatorException("The transit simulator is not reachable", false, exception);
        }
    }

    private static Integer integer(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Integer.valueOf(value.trim());
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static Double decimal(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Double.valueOf(value.trim());
        } catch (NumberFormatException exception) {
            return null;
        }
    }
}
