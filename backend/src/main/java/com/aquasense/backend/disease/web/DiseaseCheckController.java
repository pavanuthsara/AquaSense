package com.aquasense.backend.disease.web;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.aquasense.backend.disease.model.DiseaseCheck;
import com.aquasense.backend.disease.service.DiseaseCheckService;
import com.aquasense.backend.disease.service.DiseaseCheckService.CreationResult;
import com.aquasense.backend.disease.service.DiseaseCheckService.NewDiseaseCheck;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api/v1/facilities/{facilityId}/disease-checks")
public class DiseaseCheckController {
    private final DiseaseCheckService service;

    public DiseaseCheckController(DiseaseCheckService service) {
        this.service = service;
    }

    @PostMapping
    ResponseEntity<DiseaseCheckResponse> record(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 128) String requestKey,
            @Valid @RequestBody RecordDiseaseCheckRequest request) {
        CreationResult result = service.record(
                UUID.fromString(jwt.getSubject()),
                facilityId,
                requestKey,
                new NewDiseaseCheck(
                        request.predictedLabel(),
                        request.confidence(),
                        request.uncertain(),
                        request.modelVersion(),
                        request.tankLabel(),
                        request.note(),
                        request.checkedAt()));
        return ResponseEntity
                .status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(DiseaseCheckResponse.from(result.check()));
    }

    @GetMapping
    List<DiseaseCheckResponse> list(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID facilityId,
            @RequestParam(required = false) Integer limit) {
        return service.list(UUID.fromString(jwt.getSubject()), facilityId, limit).stream()
                .map(DiseaseCheckResponse::from)
                .toList();
    }

    public record RecordDiseaseCheckRequest(
            @NotBlank @Pattern(regexp = "[a-z][a-z0-9_]{0,39}") String predictedLabel,
            @NotNull @DecimalMin("0.0") @DecimalMax("1.0") Double confidence,
            @NotNull Boolean uncertain,
            @NotBlank @Size(max = 64) String modelVersion,
            @Size(max = 80) String tankLabel,
            @Size(max = 500) String note,
            @NotNull Instant checkedAt) {
    }

    public record DiseaseCheckResponse(
            UUID id,
            UUID facilityId,
            String predictedLabel,
            double confidence,
            boolean uncertain,
            String modelVersion,
            String tankLabel,
            String note,
            String checkedByName,
            Instant checkedAt) {
        static DiseaseCheckResponse from(DiseaseCheck check) {
            return new DiseaseCheckResponse(
                    check.getId(),
                    check.getFacility().getId(),
                    check.getPredictedLabel(),
                    check.getConfidence(),
                    check.isUncertain(),
                    check.getModelVersion(),
                    check.getTankLabel(),
                    check.getNote(),
                    check.getCheckedBy().getDisplayName(),
                    check.getCheckedAt());
        }
    }
}
