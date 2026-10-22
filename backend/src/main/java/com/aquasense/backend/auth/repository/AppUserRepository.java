package com.aquasense.backend.auth.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AppUserRepository extends JpaRepository<AppUser, UUID> {
    Optional<AppUser> findByGoogleSubject(String googleSubject);
    Optional<AppUser> findByEmailIgnoreCase(String email);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select user from AppUser user where user.id = :id")
    Optional<AppUser> findByIdForUpdate(@Param("id") UUID id);
}
