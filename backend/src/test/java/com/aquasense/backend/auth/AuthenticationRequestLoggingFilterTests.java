package com.aquasense.backend.auth;

import static org.assertj.core.api.Assertions.assertThat;

import com.aquasense.backend.auth.web.AuthenticationRequestLoggingFilter;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

@ExtendWith(OutputCaptureExtension.class)
class AuthenticationRequestLoggingFilterTests {
    @Test
    void logsAuthArrivalAndStatusWithoutCredentials(CapturedOutput output) throws Exception {
        var request = new MockHttpServletRequest("POST", "/api/v1/auth/register");
        request.setContent("private-password-never-log".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        request.addHeader("Authorization", "Bearer private-access-token");
        request.setQueryString("secret=private-query-value");
        new AuthenticationRequestLoggingFilter().doFilter(request, new MockHttpServletResponse(),
                (req, res) -> ((HttpServletResponse) res).setStatus(400));

        assertThat(output.getAll()).contains("Auth request started: POST /api/v1/auth/register")
                .contains("Auth request completed: POST /api/v1/auth/register -> 400")
                .doesNotContain("private-password-never-log", "private-access-token", "private-query-value");
    }

    @Test
    void ignoresOtherPaths(CapturedOutput output) throws Exception {
        new AuthenticationRequestLoggingFilter().doFilter(
                new MockHttpServletRequest("GET", "/other/private/path"),
                new MockHttpServletResponse(), (req, res) -> { });
        assertThat(output.getAll()).doesNotContain("Auth request");
    }
}
