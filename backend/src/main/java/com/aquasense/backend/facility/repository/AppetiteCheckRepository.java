package com.aquasense.backend.facility.repository;

import java.util.Collection;
import java.util.Optional;
import java.util.UUID;
import com.aquasense.backend.facility.model.AppetiteCheck;
import com.aquasense.backend.facility.model.AppetiteCheckStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AppetiteCheckRepository extends JpaRepository<AppetiteCheck, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<AppetiteCheck> findFirstByTank_IdAndStatusInOrderByRequestedAtAsc(
            UUID tankId, Collection<AppetiteCheckStatus> statuses);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from AppetiteCheck c where c.id = :id")
    Optional<AppetiteCheck> findForUpdate(@Param("id") UUID id);
}
