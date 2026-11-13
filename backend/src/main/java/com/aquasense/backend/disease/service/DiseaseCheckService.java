package com.aquasense.backend.disease.service;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import com.aquasense.backend.auth.repository.AppUserRepository;
import com.aquasense.backend.auth.web.AuthenticationFailureException;
import com.aquasense.backend.disease.model.DiseaseCheck;
import com.aquasense.backend.disease.repository.DiseaseCheckRepository;
import com.aquasense.backend.facility.model.Facility;
import com.aquasense.backend.facility.service.FacilityService;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Saves and lists disease-check results. The model itself runs on the phone;
 * the backend only keeps the history so every member of an aquarium can see it.
 */
@Service
public class DiseaseCheckService {
    public static final int DEFAULT_PAGE_SIZE = 20;
    public static final int MAX_PAGE_SIZE = 100;

    /** Allow small phone clock differences, but reject results dated in the future. */
    private static final Duration ALLOWED_CLOCK_SKEW = Duration.ofMinutes(5);

    private final AppUserRepository users;
    private final FacilityService facilityService;
    private final DiseaseCheckRepository checks;

    public DiseaseCheckService(
            AppUserRepository users,
            FacilityService facilityService,
            DiseaseCheckRepository checks) {
        this.users = users;
        this.facilityService = facilityService;
        this.checks = checks;
    }

    @Transactional
    public CreationResult record(UUID userId, UUID facilityId, String requestKey, NewDiseaseCheck input) {
        // Throws a not-found error if the user is not a member of this aquarium.
        Facility facility = facilityService.get(userId, facilityId).getFacility();
        AppUser user = users.findByIdForUpdate(userId)
                .orElseThrow(() -> new AuthenticationFailureException("The authenticated user no longer exists"));
        String key = requestKey.trim();
        Instant now = Instant.now();
        // Stored to the millisecond so a retried request compares equal to the saved row.
        Instant checkedAt = input.checkedAt().truncatedTo(ChronoUnit.MILLIS);
        if (checkedAt.isAfter(now.plus(ALLOWED_CLOCK_SKEW))) {
            throw new DiseaseCheckException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_checked_at",
                    "The check time cannot be in the future");
        }
        String tankLabel = blankToNull(input.tankLabel());
        String note = blankToNull(input.note());

        return checks.findByCheckedBy_IdAndRequestKey(userId, key)
                .map(existing -> {
                    if (!sameCheck(existing, facilityId, input, checkedAt, tankLabel, note)) {
                        throw new DiseaseCheckException(
                                HttpStatus.CONFLICT,
                                "idempotency_conflict",
                                "That request key was already used for a different disease check");
                    }
                    return new CreationResult(existing, false);
                })
                .orElseGet(() -> new CreationResult(
                        checks.save(new DiseaseCheck(
                                facility,
                                user,
                                key,
                                input.predictedLabel(),
                                input.confidence(),
                                input.uncertain(),
                                input.modelVersion().trim(),
                                tankLabel,
                                note,
                                checkedAt,
                                now)),
                        true));
    }

    @Transactional(readOnly = true)
    public List<DiseaseCheck> list(UUID userId, UUID facilityId, Integer requestedLimit) {
        facilityService.get(userId, facilityId);
        int limit = requestedLimit == null ? DEFAULT_PAGE_SIZE : requestedLimit;
        if (limit < 1 || limit > MAX_PAGE_SIZE) {
            throw new DiseaseCheckException(
                    HttpStatus.BAD_REQUEST,
                    "invalid_limit",
                    "The limit must be between 1 and " + MAX_PAGE_SIZE);
        }
        return checks.findAllByFacility_IdOrderByCheckedAtDescIdDesc(facilityId, PageRequest.of(0, limit));
    }

    private static boolean sameCheck(
            DiseaseCheck existing,
            UUID facilityId,
            NewDiseaseCheck input,
            Instant checkedAt,
            String tankLabel,
            String note) {
        return existing.getFacility().getId().equals(facilityId)
                && existing.getPredictedLabel().equals(input.predictedLabel())
                && Double.compare(existing.getConfidence(), input.confidence()) == 0
                && existing.isUncertain() == input.uncertain()
                && existing.getModelVersion().equals(input.modelVersion().trim())
                && Objects.equals(existing.getTankLabel(), tankLabel)
                && Objects.equals(existing.getNote(), note)
                && existing.getCheckedAt().truncatedTo(ChronoUnit.MILLIS).equals(checkedAt);
    }

    private static String blankToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    public record NewDiseaseCheck(
            String predictedLabel,
            double confidence,
            boolean uncertain,
            String modelVersion,
            String tankLabel,
            String note,
            Instant checkedAt) {
    }

    public record CreationResult(DiseaseCheck check, boolean created) {
    }
}
