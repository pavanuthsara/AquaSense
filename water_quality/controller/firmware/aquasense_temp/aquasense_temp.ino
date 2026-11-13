/*
 * AquaSense ESP32 — temperature node for the baseline controller
 * ----------------------------------------------------------------
 * Reads a DS18B20 water-temperature probe and POSTs it as JSON to the
 * controller running on the Mac:
 *
 *     POST http://172.28.21.128:8000/api/readings
 *     {"tank_id":"tank1","temperature":25.63}
 *
 * The server stamps the time itself, so no RTC/NTP is needed.
 *
 * Wiring (DS18B20, waterproof probe):
 *     red    -> 3V3
 *     black  -> GND
 *     yellow -> GPIO 4, plus a 4.7 kΩ resistor between GPIO 4 and 3V3
 *
 * Arduino IDE setup:
 *     Board:     "ESP32 Dev Module" (Espressif ESP32 core)
 *     Libraries: "OneWire" (Paul Stoffregen), "DallasTemperature" (Miles Burton)
 *
 * Before uploading: set WIFI_SSID / WIFI_PASS below. The Mac and the ESP32
 * must be on the SAME Wi-Fi, and the server must be started with
 *     python -m controller --host 0.0.0.0
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// ---------------------------------------------------------------- settings
const char* WIFI_SSID = "Kaveesha\xE2\x80\x99s 16";   // iPhone uses a curly apostrophe (’), not '
const char* WIFI_PASS = "12345678";

const char* SERVER_URL = "http://172.20.10.3:8000/api/readings";  // the Mac on the iPhone hotspot
const char* TANK_ID    = "tank1";

const int           ONE_WIRE_PIN   = 4;      // DS18B20 data pin
const unsigned long SEND_EVERY_MS  = 5000;   // one reading every 5 s
const int           HTTP_TIMEOUT_MS = 4000;

// ------------------------------------------------------------------ objects
OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature sensors(&oneWire);
unsigned long lastSend = 0;

// On failure, list what the ESP32 can actually see (2.4 GHz only). If the
// hotspot is missing, turn on "Maximize Compatibility" on the iPhone.
void scanNetworks() {
  int n = WiFi.scanNetworks();
  Serial.printf("Visible networks: %d\n", n);
  for (int i = 0; i < n; i++) {
    bool match = WiFi.SSID(i) == WIFI_SSID;
    Serial.printf("  %s\"%s\"  RSSI %d\n", match ? "MATCH -> " : "", WiFi.SSID(i).c_str(), WiFi.RSSI(i));
  }
  WiFi.scanDelete();
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("Connecting to Wi-Fi \"%s\"", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);               // abort any attempt still in progress, else "sta is connecting, cannot set config"
  delay(100);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nWi-Fi OK, ESP32 IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.printf("\nWi-Fi failed (status %d), will retry\n", WiFi.status());
    scanNetworks();
  }
}

void sendReading(float tempC) {
  // -127 means the probe is disconnected. It is still sent on purpose: the
  // server logs it as a SENSOR FAULT and never acts on it.
  String body = String("{\"tank_id\":\"") + TANK_ID + "\",\"temperature\":" + String(tempC, 3) + "}";

  HTTPClient http;
  http.setTimeout(HTTP_TIMEOUT_MS);
  http.begin(SERVER_URL);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(body);

  if (code == 200) {
    Serial.printf("sent %s -> 200 OK\n", body.c_str());
  } else if (code > 0) {
    Serial.printf("sent %s -> HTTP %d: %s\n", body.c_str(), code, http.getString().c_str());
  } else {
    // negative codes = connection problem (server not running, wrong IP, firewall)
    Serial.printf("POST failed: %s\n", http.errorToString(code).c_str());
  }
  http.end();
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nAquaSense temperature node");
  sensors.begin();
  Serial.printf("DS18B20 sensors found: %d\n", sensors.getDeviceCount());
  connectWiFi();
}

void loop() {
  if (millis() - lastSend < SEND_EVERY_MS) return;
  lastSend = millis();

  connectWiFi();                       // reconnects if the Wi-Fi dropped
  sensors.requestTemperatures();
  float tempC = sensors.getTempCByIndex(0);

  if (WiFi.status() == WL_CONNECTED) {
    sendReading(tempC);
  } else {
    Serial.printf("no Wi-Fi, reading %.2f °C not sent\n", tempC);
  }
}
