#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "esp_camera.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include <base64.h>
#include <ArduinoJson.h>

#include <Wire.h>
#include "SensirionI2CSen5x.h"

SensirionI2CSen5x sen5x;

// ================= WIFI =================
const char* ssid = "Redmi Note 14";
const char* password = "comelcomel12";

// ================= MQTT =================
const char* mqtt_server = "10.123.2.119";
const int   mqtt_port   = 1883;

// Topics
const char* topic_discovery = "smokeguard/sensor/discovery";
const char* topic_room_data = "smokeguard/room/data";
const char* topic_history   = "smokeguard/room/history";
const char* topic_status    = "smokeguard/sensor/status";
const char* topic_alert     = "smokeguard/room/alerts";

// ================= CAMERA PINS (AI THINKER) =================
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define FLASH_LED_PIN 4

// ================= SETTINGS =================
#define CAPTURE_INTERVAL 20000   // 20s send + picture
#define IMAGE_QUALITY    15      // sharper image
#define FRAME_SIZE       FRAMESIZE_QVGA   // clearer resolution

// ================= GLOBALS =================
WiFiClient espClient;
PubSubClient mqttClient(espClient);

String DEVICE_ID;
String ROOM_ID = "";

bool roomAssigned   = false;
bool captureEnabled = false;

unsigned long lastCaptureTime = 0;

// ================= SEN55 PARAMETERS =================
#define SAMPLE_MS     1000
#define COOLDOWN_MS   10000
#define VOC_WAIT_MS   40000
#define WARMUP_MS     30000

#define VOC_SPIKE     150
#define PM_SPIKE      150
#define PM_LIMIT_FOR_VAPE 100
#define VOC_SMALL_MAX  30
#define VOC_SLOPE_PER_S 10
#define VOC_MIN_RISE   30

const int BASELINE_WINDOW = 8;
float pmBuffer[BASELINE_WINDOW];
float vocBuffer[BASELINE_WINDOW];
int bufferIndex = 0;

float baselinePM25 = 0, baselineVOC = 0;

unsigned long lastEventEnd = 0;
unsigned long lineNo = 0;
bool ready = false;
unsigned long warmUpStartTime = 0;

// ================= FUNCTION DECL =================
void setupCamera();
void connectWiFi();
void connectMQTT();
void publishDiscovery();
void publishOnlineStatus();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void sendSensorDataOnly();
void captureAndSend(float pm2p5, float vocIndex, float noxIndex,
                    float temperature, float humidity, String statusLabel);
String encodeImage(camera_fb_t* fb);
String classifyEvent(float pm2p5, float vocIndex, float noxIndex);
void copyArray(float *src, float *dst, int len);
float median(float *buf, int len);

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);

  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, LOW);

  DEVICE_ID = "ESP32CAM-" + String((uint32_t)ESP.getEfuseMac(), HEX);

  setupCamera();
  connectWiFi();

  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(200 * 1024);

  connectMQTT();
  publishDiscovery();
  publishOnlineStatus();

  // Init SEN55
  Wire.begin(15, 14);
  sen5x.begin(Wire);
  uint16_t error;
  char errorMessage[256];
  error = sen5x.deviceReset();
  delay(100);
  error = sen5x.startMeasurement();
  delay(100);

  warmUpStartTime = millis();

  Serial.println("✅ ESP32-CAM READY (camera + SEN55)");
}

// ================= LOOP =================
unsigned long lastSensorPrint = 0;
unsigned long lastNormalCycle = 0;

void loop() {
  if (!mqttClient.connected()) {
    connectMQTT();
    publishOnlineStatus();
  }
  mqttClient.loop();

  // Print sensor values every 1 second
  if (millis() - lastSensorPrint > 1000) {
    lastSensorPrint = millis();

    float pm1p0, pm2p5, pm4p0, pm10p0;
    float humidity, temperature;
    float vocIndex, noxIndex;

    uint16_t error = sen5x.readMeasuredValues(pm1p0, pm2p5, pm4p0, pm10p0,
                                              humidity, temperature,
                                              vocIndex, noxIndex);
    if (!error) {
      Serial.print("📊 Live | Temp="); Serial.print(temperature);
      Serial.print(" °C, Hum="); Serial.print(humidity);
      Serial.print(" %, PM2.5="); Serial.print(pm2p5);
      Serial.print(" µg/m³, VOC="); Serial.print(vocIndex);
      Serial.print(", NOx="); Serial.println(noxIndex);
    } else {
      Serial.println("⚠️ Error reading SEN55 during live print");
    }
  }

  // Warm-up timer display (30 seconds)
  if (!ready && millis() - warmUpStartTime < WARMUP_MS) {
    unsigned long elapsed = millis() - warmUpStartTime;
    unsigned long remaining = WARMUP_MS - elapsed;

    static unsigned long lastWarmupPrint = 0;
    if (millis() - lastWarmupPrint > 5000) {
      lastWarmupPrint = millis();
      Serial.print("⏳ Warming up: ");
      Serial.print(remaining / 1000);
      Serial.println("s remaining...");
    }
  } else if (!ready) {
    ready = true;
    Serial.println("✅ Detection enabled.");
  }

  // Normal capture cycle every 20s (no image for normal)
  bool canSend = roomAssigned && captureEnabled && ready;
  if (canSend && (millis() - lastNormalCycle > CAPTURE_INTERVAL)) {
    lastNormalCycle = millis();
    digitalWrite(FLASH_LED_PIN, HIGH);
    delay(100);
    digitalWrite(FLASH_LED_PIN, LOW);
    sendSensorDataOnly();
  }
}

// ================= CLASSIFICATION LOGIC =================
String classifyEvent(float pm2p5, float vocIndex, float noxIndex) {
  pmBuffer[bufferIndex]  = pm2p5;
  vocBuffer[bufferIndex] = vocIndex;
  bufferIndex = (bufferIndex + 1) % BASELINE_WINDOW;

  baselinePM25 = median(pmBuffer, BASELINE_WINDOW);
  baselineVOC  = median(vocBuffer, BASELINE_WINDOW);

  float dPM  = pm2p5 - baselinePM25;
  float dVOC = vocIndex - baselineVOC;

  if (millis() - lastEventEnd < COOLDOWN_MS) {
    return "Cooldown";
  }

  if (dVOC >= VOC_SPIKE && dPM < PM_LIMIT_FOR_VAPE) {
    Serial.println("🚨 Event started - Immediate Vape Detected");
    lastEventEnd = millis();
    return "Vape Detected";
  }

  if (dPM >= PM_SPIKE) {
    Serial.println("🚨 Event started - PM spike detected, waiting for VOC...");

    bool vocRise = false;
    unsigned long t0 = millis();
    float vocPrev = vocIndex;
    int slopeStreak = 0;

    while (millis() - t0 < VOC_WAIT_MS) {
      delay(SAMPLE_MS);

      uint16_t error;
      char errorMessage[256];
      float tempPM, tempVOC, tempNOx, tempHumidity, tempTemperature;

      error = sen5x.readMeasuredValues(tempPM, pm2p5, tempPM, tempPM,
                                       tempHumidity, tempTemperature,
                                       vocIndex, tempNOx);
      if (error) {
        Serial.println("⚠️ Error reading values during VOC wait");
        break;
      }

      pmBuffer[bufferIndex]  = pm2p5;
      vocBuffer[bufferIndex] = vocIndex;
      bufferIndex = (bufferIndex + 1) % BASELINE_WINDOW;

      baselinePM25 = median(pmBuffer, BASELINE_WINDOW);
      baselineVOC  = median(vocBuffer, BASELINE_WINDOW);

      float dVOCw = vocIndex - baselineVOC;
      float dv    = vocIndex - vocPrev;
      vocPrev     = vocIndex;

      if (dv >= VOC_SLOPE_PER_S) slopeStreak++; else slopeStreak = 0;

      if (dVOCw >= VOC_SPIKE || slopeStreak >= 3) {
        vocRise = true;
        break;
      }
    }

    String result;
    if (vocRise) {
      result = "Vape Detected";
    } else {
      float finalDVOC = vocIndex - baselineVOC;
      if (finalDVOC < VOC_MIN_RISE) {
        result = "Cigarette Detected";
      } else {
        result = "Vape Detected (low-rise)";
      }
    }

    Serial.print("🚨 Classification result: ");
    Serial.println(result);
    lastEventEnd = millis();
    return result;
  }

  return "Normal";
}

// ================= SEND SENSOR DATA ONLY =================
void sendSensorDataOnly() {
  float pm1p0, pm2p5, pm4p0, pm10p0;
  float humidity, temperature;
  float vocIndex, noxIndex;

  uint16_t error;
  char errorMessage[256];
  error = sen5x.readMeasuredValues(pm1p0, pm2p5, pm4p0, pm10p0,
                                   humidity, temperature,
                                   vocIndex, noxIndex);
  if (error) {
    Serial.println("❌ Error reading SEN55");
    return;
  }

  String statusLabel = classifyEvent(pm2p5, vocIndex, noxIndex);
  bool isAlert = (statusLabel == "Vape Detected" ||
                  statusLabel == "Cigarette Detected" ||
                  statusLabel == "Vape Detected (low-rise)");

  DynamicJsonDocument doc(1024);
  doc["sensor_id"]   = DEVICE_ID;
  doc["room"]        = ROOM_ID;
  doc["temperature"] = temperature;
  doc["humidity"]    = humidity;
  doc["pm25"]        = pm2p5;
  doc["voc"]         = vocIndex;
  doc["nox"]         = noxIndex;
  doc["status"]      = statusLabel;
  doc["timestamp"]   = millis();
  doc["is_alert"]    = isAlert;

  String payload;
  serializeJson(doc, payload);

  if (isAlert) {
    captureAndSend(pm2p5, vocIndex, noxIndex, temperature, humidity, statusLabel);
  } else {
    if (mqttClient.publish(topic_room_data, payload.c_str()) &&
        mqttClient.publish(topic_history, payload.c_str())) {
      Serial.print("📡 Normal data sent | Temp="); Serial.print(temperature);
      Serial.print(" °C, PM2.5="); Serial.print(pm2p5);
      Serial.print(" µg/m³, Status="); Serial.println(statusLabel);
    }
  }
}

// ================= CAPTURE + SEND (ALERT ONLY) =================
void captureAndSend(float pm2p5, float vocIndex, float noxIndex,
                    float temperature, float humidity, String statusLabel) {

  bool isAlert = (statusLabel == "Vape Detected" ||
                  statusLabel == "Cigarette Detected" ||
                  statusLabel == "Vape Detected (low-rise)");

  if (!isAlert) {
    Serial.println("⚠️ Not an alert, skipping image capture");
    return;
  }

  digitalWrite(FLASH_LED_PIN, HIGH);
  delay(100);
  camera_fb_t* fb = esp_camera_fb_get();
  digitalWrite(FLASH_LED_PIN, LOW);

  if (!fb) {
    Serial.println("❌ Capture failed");
    return;
  }

  String img64 = encodeImage(fb);

  DynamicJsonDocument doc(30 * 1024);
  doc["sensor_id"]   = DEVICE_ID;
  doc["room"]        = ROOM_ID;
  doc["temperature"] = temperature;
  doc["humidity"]    = humidity;
  doc["pm25"]        = pm2p5;
  doc["voc"]         = vocIndex;
  doc["nox"]         = noxIndex;
  doc["status"]      = statusLabel;
  doc["image"]       = img64;
  doc["timestamp"]   = millis();
  doc["is_alert"]    = true;

  String payload;
  serializeJson(doc, payload);

  bool alertPublished = false;
  int retryCount = 0;

while (!alertPublished && retryCount < 3) {
    // Debug info before trying to publish
    Serial.print("[DEBUG] Payload length: ");
    Serial.print(payload.length());
    Serial.println(" bytes");
    Serial.print("[DEBUG] MQTT state: ");
    Serial.println(mqttClient.state());

    if (mqttClient.publish(topic_alert, payload.c_str())) {
        alertPublished = true;
        Serial.print("🚨 ALERT published | Type=");
        Serial.println(statusLabel);
    } else {
        retryCount++;
        Serial.print("❌ Failed to publish alert (attempt ");
        Serial.print(retryCount);
        Serial.println("), retrying...");
        delay(1000);

        if (!mqttClient.connected()) {
            Serial.println("⚠️ MQTT disconnected during retry, reconnecting...");
            connectMQTT();
        }
    }
}

  if (!alertPublished) {
    Serial.println("❌ Alert failed after 3 retries");
  }

  esp_camera_fb_return(fb);
  lastNormalCycle = millis();
}

// ================= IMAGE =================
String encodeImage(camera_fb_t* fb) {
  return base64::encode(fb->buf, fb->len);
}

// ================= CAMERA =================
void setupCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAME_SIZE;
  config.jpeg_quality = IMAGE_QUALITY;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("❌ Camera init failed");
    ESP.restart();
  }
}

// ================= WIFI =================
void connectWiFi() {
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("📡 WiFi connected: ");
  Serial.println(WiFi.localIP());
}

// ================= MQTT =================
void connectMQTT() {
  String clientId = DEVICE_ID;

  // LWT FIX: publish to the same status topic with {"status":"offline"}
  String lwtPayload = String("{\"sensor_id\":\"") + DEVICE_ID + "\",\"status\":\"offline\"}";

  String controlTopic = String("smokeguard/sensors/") + DEVICE_ID + "/control";

  mqttClient.setKeepAlive(60);

  while (!mqttClient.connected()) {
    Serial.println("🔌 Connecting to MQTT...");
    if (mqttClient.connect(clientId.c_str(),
                           NULL, NULL,
                           topic_status, 0, true,
                           lwtPayload.c_str())) {
      mqttClient.subscribe(controlTopic.c_str());
      Serial.println("🔗 MQTT connected");
      Serial.print("🔔 Subscribed: ");
      Serial.println(controlTopic);
    } else {
      Serial.print("❌ MQTT connect failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(", retrying in 3s...");
      delay(3000);
    }
  }
}

void publishDiscovery() {
  DynamicJsonDocument doc(256);
  doc["sensor_id"] = DEVICE_ID;
  doc["status"]    = "camera+sen55";

  String payload;
  serializeJson(doc, payload);

  mqttClient.publish(topic_discovery, payload.c_str());
  Serial.println("📡 Discovery published: " + payload);
}

void publishOnlineStatus() {
  DynamicJsonDocument doc(128);
  doc["sensor_id"] = DEVICE_ID;
  doc["status"]    = "online";
  String payload;
  serializeJson(doc, payload);
  // Retained online—broker will replace with LWT offline on drop
  mqttClient.publish(topic_status, payload.c_str(), true);
  Serial.println("📡 Status published: " + payload);
}

// ================= CONTROL =================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  payload[length] = '\0';
  String msg = String((char*)payload);

  Serial.print("📨 Control message received on ");
  Serial.print(topic);
  Serial.print(": ");
  Serial.println(msg);

  DynamicJsonDocument doc(256);
  if (deserializeJson(doc, msg)) {
    Serial.println("⚠️ Control JSON parse failed");
    return;
  }

  if (doc.containsKey("sensor_id") &&
      doc["sensor_id"].as<String>() != DEVICE_ID) return;

  if (doc.containsKey("room")) {
    ROOM_ID = doc["room"].as<String>();
    roomAssigned = (ROOM_ID.length() > 0);
    Serial.println("🏠 Room assigned: " + ROOM_ID);
  }

  if (doc.containsKey("is_active")) {
    captureEnabled = doc["is_active"];
    Serial.println(captureEnabled ? "▶️ Sensor ON" : "⏸️ Sensor OFF");
  }
}

// ================= HELPERS =================
void copyArray(float *src, float *dst, int len) {
  for (int i = 0; i < len; i++) dst[i] = src[i];
}

float median(float *buf, int len) {
  static float tmp[BASELINE_WINDOW];
  copyArray(buf, tmp, len);
  for (int i = 1; i < len; i++) {
    float key = tmp[i]; int j = i - 1;
    while (j >= 0 && tmp[j] > key) { tmp[j + 1] = tmp[j]; j--; }
    tmp[j + 1] = key;
  }
  if (len % 2 == 1) return tmp[len / 2];
  return (tmp[len / 2 - 1] + tmp[len / 2]) / 2.0;
}