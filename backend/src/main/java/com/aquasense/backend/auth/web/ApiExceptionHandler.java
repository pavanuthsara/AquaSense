package com.aquasense.backend.auth.web;

import java.time.Instant;
import java.util.Map;

import com.aquasense.backend.disease.service.DiseaseCheckException;
import com.aquasense.backend.facility.service.FacilityException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(AuthenticationFailureException.class)
    ResponseEntity<Map<String, Object>> authenticationFailure(AuthenticationFailureException exception) {
        return error(HttpStatus.UNAUTHORIZED, "authentication_failed", exception.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<Map<String, Object>> validationFailure(MethodArgumentNotValidException exception) {
        return error(HttpStatus.BAD_REQUEST, "invalid_request", "The request is missing required information");
    }

    @ExceptionHandler(FacilityException.class)
    ResponseEntity<Map<String, Object>> facilityFailure(FacilityException exception) {
        return error(exception.getStatus(), exception.getCode(), exception.getMessage());
    }

    @ExceptionHandler(DiseaseCheckException.class)
    ResponseEntity<Map<String, Object>> diseaseCheckFailure(DiseaseCheckException exception) {
        return error(exception.getStatus(), exception.getCode(), exception.getMessage());
    }

    private ResponseEntity<Map<String, Object>> error(HttpStatus status, String code, String message) {
        return ResponseEntity.status(status).body(Map.of(
                "code", code,
                "message", message,
                "timestamp", Instant.now().toString()));
    }
}
