from flask import Flask, jsonify, request
from flask_cors import CORS
import paho.mqtt.client as mqtt
import threading
import json
import time
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, firestore
import requests
from requests.exceptions import RequestException

# ---------------- Configuration ----------------
MQTT_BROKER = "localhost"
MQTT_PORT = 1883

MQTT_TOPIC_DISCOVERY = "smokeguard/sensor/discovery"
MQTT_TOPIC_ROOM_DATA = "smokeguard/room/data"
MQTT_TOPIC_SENSOR_HISTORY = "smokeguard/room/history"
MQTT_TOPIC_ALERTS = "smokeguard/room/alerts"
MQTT_TOPIC_SENSOR_CONTROL_PREFIX = "smokeguard/sensors"
MQTT_TOPIC_SENSOR_STATUS = "smokeguard/sensor/status"

# ImgBB
IMGBB_API_KEY = "985c2008730a770c3e3caa6be03accf8"   # replace with your key
IMGBB_UPLOAD_URL = "https://api.imgbb.com/1/upload"

# ---------------- Firebase Initialization ----------------
cred = credentials.Certificate(r"C:\\Users\\adzim\\Desktop\\PythonTest\\serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()
print("✅ Firebase initialized successfully")

latest_sensors = {}  # cache keyed by sensor_id
mqtt_connected = False

# ---------------- Helpers ----------------
def normalize_room(room):
    if not room:
        return None
    room = str(room).strip()
    if not room:
        return None
    if room.lower().startswith("room"):
        num = room.replace("Room", "").replace("room", "").strip()
        return f"Room {num}" if num else None
    return f"Room {room}"

def safe_iso(dt):
    return dt.isoformat() if isinstance(dt, datetime) else dt

def upload_to_imgbb(base64_image):
    if not base64_image:
        return None
    try:
        resp = requests.post(
            IMGBB_UPLOAD_URL,
            data={"key": IMGBB_API_KEY, "image": base64_image},
            timeout=15
        )
        if resp.status_code == 200:
            data = resp.json()
            return data.get("data", {}).get("url")
        else:
            print(f"❌ ImgBB upload failed: {resp.status_code} {resp.text}")
            return None
    except RequestException as e:
        print(f"❌ ImgBB request error: {e}")
        return None

def resolve_room_for_sensor(sensor_id):
    # Try cache first
    room = latest_sensors.get(sensor_id, {}).get("room")
    if room:
        return room
    # Fallback to Firestore
    try:
        sdoc = db.collection("sensors").document(sensor_id).get()
        if sdoc.exists:
            return sdoc.to_dict().get("room")
    except Exception as e:
        print(f"⚠️ Firestore room resolve error: {e}")
    return None

# ---------------- MQTT Callbacks ----------------
def on_connect(client, userdata, flags, rc, properties=None):
    global mqtt_connected
    if rc == 0:
        mqtt_connected = True
        client.subscribe([
            (MQTT_TOPIC_DISCOVERY, 0),
            (MQTT_TOPIC_ROOM_DATA, 0),
            (MQTT_TOPIC_SENSOR_HISTORY, 0),
            (MQTT_TOPIC_ALERTS, 0),
            (MQTT_TOPIC_SENSOR_STATUS, 0)
        ])
        print("📡 MQTT connected & subscribed")
    else:
        mqtt_connected = False
        print(f"❌ MQTT connect failed: {rc}")

def on_disconnect(client, userdata, rc, properties=None):
    global mqtt_connected
    mqtt_connected = False
    print(f"⚠️ MQTT disconnected: {rc}")

def on_message(client, userdata, msg):
    global latest_sensors
    try:
        payload = json.loads(msg.payload.decode())
        timestamp = datetime.utcnow()

        # -------- SENSOR DISCOVERY --------
        if msg.topic == MQTT_TOPIC_DISCOVERY:
            sensor_id = payload.get("sensor_id")
            if not sensor_id:
                return

            sensor_data = {
                "sensor_id": sensor_id,
                "room": latest_sensors.get(sensor_id, {}).get("room"),  # keep existing if any
                "status": "online",
                "is_active": latest_sensors.get(sensor_id, {}).get("is_active", False),
                "last_update": timestamp,
                "created_at": timestamp
            }
            db.collection("sensors").document(sensor_id).set(sensor_data, merge=True)
            latest_sensors[sensor_id] = sensor_data
            print(f"📡 Discovered sensor {sensor_id}")

            # Auto-reply if sensor already has a room
            existing = db.collection("sensors").document(sensor_id).get()
            if existing.exists:
                data = existing.to_dict()
                room = data.get("room")
                is_active = data.get("is_active", True)
                if room:
                    control_topic = f"{MQTT_TOPIC_SENSOR_CONTROL_PREFIX}/{sensor_id}/control"
                    control_payload = json.dumps({
                        "sensor_id": sensor_id,
                        "room": room,
                        "is_active": is_active
                    })
                    client.publish(control_topic, control_payload, qos=0, retain=False)
                    print(f"📡 Sent auto-control to {control_topic}: {control_payload}")

        # -------- ROOM DATA --------
        elif msg.topic == MQTT_TOPIC_ROOM_DATA:
            sensor_id = payload.get("sensor_id")
            if not sensor_id:
                print("⚠️ ROOM_DATA missing sensor_id, skipping")
                return

            # Resolve room: prefer payload, else Firestore mapping
            room_raw = payload.get("room")
            room = normalize_room(room_raw) if room_raw else None
            if not room:
                room = resolve_room_for_sensor(sensor_id)

            # Upload image to ImgBB (if present)
            image_b64 = payload.get("image")
            image_url = upload_to_imgbb(image_b64) if image_b64 else None

            # Always add to history (even if room missing)
            history_entry = {
                "sensor_id": sensor_id,
                "room": room,
                "temperature": payload.get("temperature"),
                "humidity": payload.get("humidity"),
                "pm25": payload.get("pm25"),
                "voc": payload.get("voc"),
                "nox": payload.get("nox"),
                "status": payload.get("status", "Normal"),
                "image_url": image_url,
                "timestamp": timestamp
            }
            db.collection("sensor_history").add(history_entry)

            if not room:
                print(f"⚠️ ROOM_DATA: no room resolved for sensor_id={sensor_id}. History saved; rooms update skipped.")
                return

            # Build room snapshot
            room_data = {
                "room": room,
                "temperature": payload.get("temperature"),
                "humidity": payload.get("humidity"),
                "pm25": payload.get("pm25"),
                "voc": payload.get("voc"),
                "nox": payload.get("nox"),
                "status": payload.get("status", "Normal"),  # classification
                "image_url": image_url,
                "last_update": timestamp
            }

            sensor_data = {
                "sensor_id": sensor_id,
                "room": room,
                "status": "online",  # connectivity comes from STATUS topic
                "is_active": latest_sensors.get(sensor_id, {}).get("is_active", True),
                "last_update": timestamp
            }


            db.collection("rooms").document(room).set(room_data, merge=True)
            db.collection("sensors").document(sensor_id).set(sensor_data, merge=True)
            latest_sensors[sensor_id] = sensor_data
            print(f"✅ ROOM_DATA stored for {room} from {sensor_id}")

        # -------- HISTORY (direct topic) --------
        elif msg.topic == MQTT_TOPIC_SENSOR_HISTORY:
            payload["timestamp"] = timestamp
            # If payload has base64 image, convert to URL for consistency
            image_b64 = payload.get("image")
            if image_b64 and not payload.get("image_url"):
                payload["image_url"] = upload_to_imgbb(image_b64)
                payload.pop("image", None)
            db.collection("sensor_history").add(payload)
            print("🗂️ HISTORY entry added")

        # -------- ALERTS --------
        elif msg.topic == MQTT_TOPIC_ALERTS:
            room = normalize_room(payload.get("room"))
            
            # Get actual status from ESP32
            esp_status = payload.get("status", "Smoke Detected")  # Use ESP32's status
            
            # Upload image
            image_b64 = payload.get("image")
            image_url = upload_to_imgbb(image_b64) if image_b64 else None
            
            # Create alert with ESP32's actual status
            alert = {
                "room": room,
                "type": esp_status,  # Use ESP32 status like "Vape Detected"
                "status": "critical",  # Severity level
                "pm25": payload.get("pm25"),
                "voc": payload.get("voc"),
                "nox": payload.get("nox"),
                "temperature": payload.get("temperature"),
                "humidity": payload.get("humidity"),
                "sensor_id": payload.get("sensor_id"),
                "image_url": image_url,
                "timestamp": timestamp
            }
            
            db.collection("alerts").add(alert)
            
            # Update room status with the actual detection type
            if room:
                db.collection("rooms").document(room).set({
                    "status": esp_status,  # Update with "Vape Detected" or "Cigarette Detected"
                    "last_update": timestamp
                }, merge=True)
            
            print(f"🚨 ALERT stored: {esp_status} for {room or 'unknown room'}")
        # -------- STATUS (online/offline) --------
        elif msg.topic == MQTT_TOPIC_SENSOR_STATUS:
            sensor_id = payload.get("sensor_id")
            status = payload.get("status")
            if not sensor_id or not status:
                print("⚠️ STATUS missing fields")
                return

            timestamp = datetime.utcnow()
            db.collection("sensors").document(sensor_id).set({
                "status": status,
                "last_update": timestamp
            }, merge=True)

            latest_sensors.setdefault(sensor_id, {})
            latest_sensors[sensor_id]["status"] = status
            latest_sensors[sensor_id]["last_update"] = timestamp

            print(f"🛰️ STATUS update: {sensor_id} -> {status}")
    except Exception as e:
        print("❌ MQTT error:", e)

def setup_mqtt_client():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect
    return client

def mqtt_thread():
    client = setup_mqtt_client()
    while True:
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, 60)
            client.loop_forever()
        except Exception as e:
            print(f"⚠️ MQTT loop error: {e}")
            time.sleep(5)

threading.Thread(target=mqtt_thread, daemon=True).start()

# ---------------- Flask API ----------------
app = Flask(__name__)
CORS(app)

@app.route("/sensors", methods=["GET"])
def get_sensors():
    docs = db.collection("sensors").stream()
    sensors = []
    for d in docs:
        data = d.to_dict()
        data["last_update"] = safe_iso(data.get("last_update"))
        sensors.append(data)

    return jsonify({
        "status": "success",
        "mqtt_connected": mqtt_connected,
        "count": len(sensors),
        "sensors": sensors
    })

@app.route("/add_sensor", methods=["POST"])
def add_sensor():
    try:
        data = request.get_json(force=True)
        sensor_id = data.get("sensor_id")
        room_raw = data.get("room")
        room = normalize_room(room_raw)

        if not sensor_id or not room:
            return jsonify({"status": "error", "message": "sensor_id and room are required"}), 400

        timestamp = datetime.utcnow()

        db.collection("sensors").document(sensor_id).set({
            "sensor_id": sensor_id,
            "room": room,
            "status": "online",
            "is_active": False,
            "last_update": timestamp,
            "created_at": timestamp
        }, merge=True)

        db.collection("rooms").document(room).set({
            "room": room,
            "status": "Normal",
            "temperature": None,
            "humidity": None,
            "pm25": None,
            "voc": None,
            "nox": None,
            "image_url": None,
            "last_update": timestamp
        }, merge=True)

        latest_sensors[sensor_id] = {
            "sensor_id": sensor_id,
            "room": room,
            "status": "online",
            "is_active": True,
            "last_update": timestamp
        }

        return jsonify({"status": "success", "message": f"Sensor {sensor_id} assigned to {room}"}), 200

    except Exception as e:
        print("❌ add_sensor error:", e)
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/sensors/<sensor_id>/toggle", methods=["POST"])
def toggle_sensor(sensor_id):
    try:
        data = request.get_json(force=True)
        is_active = data.get("is_active")
        if is_active is None:
            return jsonify({"status": "error", "message": "is_active field is required"}), 400

        timestamp = datetime.utcnow()

        room_name = resolve_room_for_sensor(sensor_id)

        # Update sensors doc
        db.collection("sensors").document(sensor_id).set({
            "is_active": is_active,
            "last_update": timestamp
        }, merge=True)

        # Update room doc if known
        if room_name:
            db.collection("rooms").document(room_name).set({
                "last_update": timestamp
            }, merge=True)

        # Update cache
        latest_sensors.setdefault(sensor_id, {})
        latest_sensors[sensor_id]["is_active"] = is_active
        latest_sensors[sensor_id]["last_update"] = timestamp
        if room_name:
            latest_sensors[sensor_id]["room"] = room_name

        # Publish MQTT control
        control_topic = f"{MQTT_TOPIC_SENSOR_CONTROL_PREFIX}/{sensor_id}/control"
        payload = json.dumps({
            "sensor_id": sensor_id,
            "room": room_name,
            "is_active": is_active
        })

        client = setup_mqtt_client()
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, 60)
            client.publish(control_topic, payload, qos=0, retain=False)
            client.disconnect()
            print(f"📡 Published control to {control_topic}: {payload}")
        except Exception as e:
            print(f"❌ MQTT publish error: {e}")

        return jsonify({
            "status": "success",
            "sensor_id": sensor_id,
            "room": room_name,
            "is_active": is_active
        }), 200

    except Exception as e:
        print("❌ toggle_sensor error:", e)
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == "__main__":
    print("🚀 Flask running at http://127.0.0.1:5000")
    app.run(host="0.0.0.0", port=5000, debug=True)
