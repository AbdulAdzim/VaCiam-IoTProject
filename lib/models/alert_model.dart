import 'package:flutter/material.dart';

enum AlertStatus { critical, warning, resolved }

class AlertModel {
  final String id;
  final String room;
  final String type;
  final String time;
  final AlertStatus status;

  // Optional fields
  final double? pm25;
  final double? co2;
  final double? temperature;
  final double? humidity;
  final String? imageUrl;

  AlertModel({
    required this.id,
    required this.room,
    required this.type,
    required this.time,
    required this.status,
    this.pm25,
    this.co2,
    this.temperature,
    this.humidity,
    this.imageUrl,
  });

  // Status color for UI
  Color get statusColor {
    switch (status) {
      case AlertStatus.critical:
        return Colors.red;
      case AlertStatus.warning:
        return Colors.orange;
      case AlertStatus.resolved:
      return Colors.green;
    }
  }
}
