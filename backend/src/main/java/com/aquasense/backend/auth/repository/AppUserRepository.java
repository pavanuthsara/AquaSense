package com.aquasense.backend.auth.repository;

import java.util.Optional;
import java.util.UUID;

import com.aquasense.backend.auth.model.AppUser;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AppUserRepository extends JpaRepository<AppUser, UUID> {
    Optional<AppUser> findByGoogleSubject(String googleSubject);
    boolean existsByEmailIgnoreCaseAndGoogleSubjectNot(String email, String googleSubject);
}
