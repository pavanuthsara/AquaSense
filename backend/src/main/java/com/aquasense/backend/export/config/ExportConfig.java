package com.aquasense.backend.export.config;

import com.aquasense.backend.export.client.ExportSimulator;
import com.aquasense.backend.export.client.HttpExportSimulator;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(ExportSimulatorProperties.class)
public class ExportConfig {
    @Bean
    ExportSimulator exportSimulator(ExportSimulatorProperties properties) {
        return new HttpExportSimulator(properties);
    }
}
