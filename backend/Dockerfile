# Build and test with Java 21; no host Java or Maven installation is required.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY src ./src
RUN mvn -B -ntp clean verify

FROM eclipse-temurin:21-jre-jammy AS runtime
WORKDIR /app
RUN groupadd --system aquasense && useradd --system --gid aquasense aquasense
COPY --from=build --chown=aquasense:aquasense /workspace/target/backend-0.0.1-SNAPSHOT.jar app.jar
USER aquasense
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
