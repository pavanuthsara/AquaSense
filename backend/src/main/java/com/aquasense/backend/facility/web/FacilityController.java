package com.aquasense.backend.facility.web;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.model.FacilityMembership;
import com.aquasense.backend.facility.model.FacilityRole;
import com.aquasense.backend.facility.service.FacilityService;
import com.aquasense.backend.facility.service.FacilityService.CreationResult;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api/v1/facilities")
public class FacilityController {
    private final FacilityService facilityService;

    public FacilityController(FacilityService facilityService) {
        this.facilityService = facilityService;
    }

    @PostMapping
    ResponseEntity<FacilityResponse> create(
            @AuthenticationPrincipal Jwt jwt,
            @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) String requestKey,
            @Valid @RequestBody CreateFacilityRequest request) {
        CreationResult result = facilityService.create(
                UUID.fromString(jwt.getSubject()), requestKey, request.name(), request.timeZone());
        return ResponseEntity
                .status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(FacilityResponse.from(result.membership()));
    }

    @GetMapping
    List<FacilityResponse> list(@AuthenticationPrincipal Jwt jwt) {
        return facilityService.list(UUID.fromString(jwt.getSubject())).stream()
                .map(FacilityResponse::from)
                .toList();
    }

    @GetMapping("/timezones")
    List<String> listTimeZones() {
        return facilityService.listTimeZones();
    }

    @GetMapping("/{facilityId}")
    FacilityResponse get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID facilityId) {
        return FacilityResponse.from(facilityService.get(UUID.fromString(jwt.getSubject()), facilityId));
    }

    public record CreateFacilityRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank @Size(max = 64) String timeZone) {
    }

    public record FacilityResponse(
            UUID id,
            String name,
            String timeZone,
            FacilityRole role,
            Instant createdAt) {
        static FacilityResponse from(FacilityMembership membership) {
            Facility facility = membership.getFacility();
            return new FacilityResponse(
                    facility.getId(),
                    facility.getName(),
                    facility.getTimeZone(),
                    membership.getRole(),
                    facility.getCreatedAt());
        }
    }
}
