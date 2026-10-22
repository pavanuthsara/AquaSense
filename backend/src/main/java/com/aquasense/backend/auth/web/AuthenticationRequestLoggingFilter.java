package com.aquasense.backend.auth.web;

import java.io.IOException;
import java.util.Set;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class AuthenticationRequestLoggingFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(AuthenticationRequestLoggingFilter.class);
    private static final Set<String> PATHS = Set.of(
            "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/google/exchange",
            "/api/v1/auth/refresh", "/api/v1/auth/logout", "/api/v1/auth/me");

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !PATHS.contains(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        long started = System.nanoTime();
        // Log only known paths and timing, never bodies, headers, or query strings.
        log.info("Auth request started: {} {}", request.getMethod(), request.getRequestURI());
        try {
            chain.doFilter(request, response);
        } finally {
            log.info("Auth request completed: {} {} -> {} ({} ms)",
                    request.getMethod(), request.getRequestURI(), response.getStatus(),
                    (System.nanoTime() - started) / 1_000_000);
        }
    }
}
