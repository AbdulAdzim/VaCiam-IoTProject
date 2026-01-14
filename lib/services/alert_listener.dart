import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vaciam/services/notification.dart';

class AlertListener {
  static bool _started = false;
  
  static void start() {
    if (_started) return; // prevent multiple listeners
    _started = true;

    final alertsRef = FirebaseFirestore.instance
        .collection('alerts')
        .orderBy('time');

    // Record the current time, ignore old alerts
    final startTime = Timestamp.now();

    alertsRef
        .where('time', isGreaterThan: startTime)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            debugPrint("🔹 New alert data: $data");
            NotificationService.showNotification(
              title: "🚨 VaCiam Alert",
              body: "${data['room']} - ${data['status']}",
            );
          }
        }
      }
    }, onError: (error) {
      debugPrint("❌ Firestore listener error: $error");
    });

    debugPrint("🔹 AlertListener started at $startTime");
  }
}
