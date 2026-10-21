package com.aquasense.backend.facility.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.facility.model.DeviceType;
import com.aquasense.backend.facility.model.TankDevice;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TankDeviceRepository extends JpaRepository<TankDevice, UUID> {
    List<TankDevice> findByTank_Id(UUID tankId);

    Optional<TankDevice> findByTank_IdAndType(UUID tankId, DeviceType type);

    List<TankDevice> findByTank_Facility_IdAndTank_ArchivedAtIsNull(UUID facilityId);
}
