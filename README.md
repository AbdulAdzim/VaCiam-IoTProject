# VaCiam - Smart based iot cigarettes and vape air monitoring system
**📌 Overview**
VaCiam is a smart IoT-based monitoring system designed to detect and analyze air quality affected by cigarette and vape usage. The system leverages sensors, microcontrollers, and cloud integration to provide real-time monitoring and reporting.
This project was developed as part of my Final Year Project (Bachelor of Software Engineering, UPSI).
**🚀 Features**
Real-time detection of cigarette and vape smoke particles.
Air quality monitoring using Sensirion SEN55 sensor.
Image capture and processing with ESP32-CAM-MB microcontroller.
Data storage and retrieval via Firebase.
Image hosting integration with imgBB.
Local server communication using Flask.
Secure tunneling with ngrok.
Cross-platform support (Android, iOS, Web, Desktop).
**🛠️ Technologies Used**
Microcontroller: ESP32-CAM-MB
Sensor: Sensirion SEN55
Database: Firebase
Server: Flask (Local)
Network Protocol: MQTT
Tunnel Broker: ngrok
IDE: Visual Studio Code
Design Tools: Canva
**📂 Project Structure**
android/, ios/, web/, windows/, macos/, linux/ → Platform-specific builds
lib/ → Core application logic (Flutter/Dart)
smokeGuard.ino → Arduino sketch for ESP32 sensor integration
assets/images/ → Project visuals and resources
pubspec.yaml → Dependencies and configuration
flask_server.py → local flask server
**🎯 Results & Impact**
Provides real-time monitoring of cigarette and vape smoke.
Demonstrates integration of IoT hardware with cloud services.
Potential applications in public health monitoring, schools, and workplaces.
