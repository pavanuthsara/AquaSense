package com.aquasense.backend.facility.model;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.Instant;

import org.junit.jupiter.api.Test;

class TankDeviceTests {
    private static final Instant NOW = Instant.parse("2026-10-20T10:00:00Z");

    @Test
    void derivesOnlineStaleOfflineAndUnhealthyStatesFromHeartbeatAge() {
        TankDevice device = new TankDevice(null, DeviceType.CAMERA, "hash", NOW.minusSeconds(1000));
        assertEquals(DeviceOperationalState.OFFLINE, device.stateAt(NOW));

        device.recordHeartbeat(true, null, NOW.minusSeconds(601));
        assertEquals(DeviceOperationalState.OFFLINE, device.stateAt(NOW));

        device.recordHeartbeat(true, null, NOW.minusSeconds(121));
        assertEquals(DeviceOperationalState.STALE, device.stateAt(NOW));

        device.recordHeartbeat(true, null, NOW.minusSeconds(30));
        assertEquals(DeviceOperationalState.ONLINE, device.stateAt(NOW));

        device.recordHeartbeat(false, "Lens blocked", NOW.minusSeconds(30));
        assertEquals(DeviceOperationalState.UNHEALTHY, device.stateAt(NOW));
    }
}
