import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_bar_widget.dart';
import '../models/alert_model.dart';
import 'AQI_formula.dart';

class DashboardScreen extends StatefulWidget {
  final String selectedRoom;
  final List<String>? rooms;
  final Function(String)? onRoomChanged;

  const DashboardScreen({
    Key? key,
    required this.selectedRoom,
    this.rooms,
    this.onRoomChanged,
  }) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late String currentRoom;

  @override
  void initState() {
    super.initState();
    currentRoom = widget.selectedRoom;
    debugPrint("🔹 DashboardScreen init for room: $currentRoom");
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedRoom != widget.selectedRoom) {
      setState(() {
        currentRoom = widget.selectedRoom;
      });
      debugPrint("🔹 DashboardScreen updated to room: $currentRoom");
    }
  }

  // Dynamic color calculation based on value and thresholds
  List<Color> _getMetricColors(String metricType, double value) {
    switch (metricType) {
      case 'PM2.5':
        if (value <= 12) return [const Color(0xFF10B981), const Color(0xFF059669)]; // Good
        if (value <= 35.4) return [const Color(0xFFFACC15), const Color(0xFFEAB308)]; // Moderate
        if (value <= 55.4) return [const Color(0xFFF97316), const Color(0xFFEA580C)]; // Unhealthy for Sensitive
        if (value <= 150.4) return [const Color(0xFFEF4444), const Color(0xFFDC2626)]; // Unhealthy
        if (value <= 250.4) return [const Color(0xFF9333EA), const Color(0xFF7E22CE)]; // Very Unhealthy
        return [const Color(0xFF991B1B), const Color(0xFF7F1D1D)]; // Hazardous

      case 'VOC':
        if (value <= 250) return [const Color(0xFF10B981), const Color(0xFF059669)]; // Good
        if (value <= 1000) return [const Color(0xFFFACC15), const Color(0xFFEAB308)]; // Moderate
        if (value <= 3000) return [const Color(0xFFF97316), const Color(0xFFEA580C)]; // Poor
        return [const Color(0xFFEF4444), const Color(0xFFDC2626)]; // Critical

      case 'Temperature':
        if (value >= 20 && value <= 24) return [const Color(0xFF10B981), const Color(0xFF059669)]; // Ideal
        if ((value >= 18 && value < 20) || (value > 24 && value <= 27)) return [const Color(0xFFFACC15), const Color(0xFFEAB308)]; // Acceptable
        if (value < 18 || value > 27) return [const Color(0xFFF97316), const Color(0xFFEA580C)]; // Uncomfortable
        return [const Color(0xFFEF4444), const Color(0xFFDC2626)]; // Extreme

      case 'Humidity':
        if (value >= 40 && value <= 60) return [const Color(0xFF10B981), const Color(0xFF059669)]; // Comfortable
        if ((value >= 30 && value < 40) || (value > 60 && value <= 70)) return [const Color(0xFFFACC15), const Color(0xFFEAB308)]; // Acceptable
        if (value < 30 || value > 70) return [const Color(0xFFF97316), const Color(0xFFEA580C)]; // Uncomfortable
        return [const Color(0xFFEF4444), const Color(0xFFDC2626)]; // Extreme

      default:
        return [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: CustomAppBar(
        selectedRoom: currentRoom,
        rooms: widget.rooms,
        onRoomChanged: widget.onRoomChanged,
        assetLogoPath: 'assets/images/VaCiam.png',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .doc(currentRoom)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text(
                    'Error loading air quality data',
                    style: TextStyle(color: Colors.red),
                  );
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Text(
                    "No air quality data available.",
                    style: TextStyle(color: Colors.red),
                  );
                }

                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

                return Column(
                  children: [
                    _buildStatusCard(data),
                    const SizedBox(height: 16),
                    _buildAirQualityGrid(data),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('alerts')
                  .where('room', isEqualTo: currentRoom)
                  .orderBy('time', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final alerts = docs.map((doc) {
                  final map = doc.data() as Map<String, dynamic>;
                  return AlertModel(
                    id: doc.id,
                    room: map['room'] ?? 'Unknown',
                    type: map['type'] ?? 'Unknown Alert',
                    time: (map['time'] as Timestamp?)?.toDate().toString() ?? 'Unknown Time',
                    status: _parseStatus(map['status'] ?? 'resolved'),
                  );
                }).toList();

                return _buildAlertsSummary(alerts);
              },
            ),
          ],
        ),
      ),
    );
  }

  AlertStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'critical':
        return AlertStatus.critical;
      case 'warning':
        return AlertStatus.warning;
      default:
        return AlertStatus.resolved;
    }
  }

  Widget _buildStatusCard(Map<String, dynamic> data) {
    final aqi = CompositeAQI.evaluate(
      pm25: (data['pm25'] ?? 0).toDouble(),
      nox: (data['nox'] ?? 0).toDouble(),
    );

    Color statusColor = aqi['color'];
    String statusText = aqi['category'];
    IconData statusIcon = Icons.air; // you can change icon per category
    Color bgGradientStart = aqi['color'];
    Color bgGradientEnd = aqi['color'].withOpacity(0.8);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgGradientStart, bgGradientEnd],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(statusIcon, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Air Quality Status',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAirQualityGrid(Map<String, dynamic> data) {
    double pm25 = (data['pm25'] ?? 0).toDouble();
    double voc = (data['voc'] ?? 0).toDouble();
    double temperature = (data['temperature'] ?? 0).toDouble();
    double humidity = (data['humidity'] ?? 0).toDouble();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildModernMetricCard(
                'PM2.5',
                pm25.toString(),
                'μg/m³',
                Icons.air,
                pm25,
                'PM2.5',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModernMetricCard(
                'VOC',
                voc.toString(),
                'ppb',
                Icons.flare,
                voc,
                'VOC',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildModernMetricCard(
                'Temp',
                temperature.toString(),
                '°C',
                Icons.thermostat,
                temperature,
                'Temperature',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModernMetricCard(
                'Humidity',
                humidity.toString(),
                '%',
                Icons.water_drop,
                humidity,
                'Humidity',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModernMetricCard(
    String label,
    String value,
    String unit,
    IconData icon,
    double metricValue,
    String metricType,
  ) {
    // Get dynamic colors based on metric value and type
    final colors = _getMetricColors(metricType, metricValue);
    final colorStart = colors[0];
    final colorEnd = colors[1];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dynamic gradient background accent that changes based on value
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorStart, colorEnd],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorStart.withOpacity(0.2), colorEnd.withOpacity(0.1)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colorStart, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSummary(List<AlertModel> alerts) {
    int cigaretteCount = alerts.where((a) => 
      a.type.toLowerCase().contains('cigarette') || 
      a.type.toLowerCase().contains('smoke')
    ).length;
    
    int vapeCount = alerts.where((a) => 
      a.type.toLowerCase().contains('vape') || 
      a.type.toLowerCase().contains('vapor')
    ).length;
    
    int totalAlerts = alerts.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  color: Color(0xFF2563EB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Detection Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalAlerts Total',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          if (totalAlerts == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No detections',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Area is clear and safe',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                _buildDetectionRow(
                  'Cigarrete Detected',
                  cigaretteCount,
                  const Color(0xFFEF4444),
                  Icons.smoking_rooms,
                ),
                const SizedBox(height: 12),
                _buildDetectionRow(
                  'Vape Detected',
                  vapeCount,
                  const Color(0xFF8B5CF6),
                  Icons.vaping_rooms,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDetectionRow(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}