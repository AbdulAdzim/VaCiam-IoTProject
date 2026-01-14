import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_bar_widget.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'AQI_formula.dart';

class AirQualityScreen extends StatefulWidget {
  final String selectedRoom;
  final List<String>? rooms;
  final Function(String)? onRoomChanged;

  const AirQualityScreen({
    Key? key,
    required this.selectedRoom,
    this.rooms,
    this.onRoomChanged,
  }) : super(key: key);

  @override
  State<AirQualityScreen> createState() => _AirQualityScreenState();
}

class _AirQualityScreenState extends State<AirQualityScreen> {
  String selectedTimeRange = '24h';
  String selectedMetric = 'PM2.5';
  bool _showAllReadings = false;
  DateTime? _selectedDate; // NEW: Selected date for filtering

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: CustomAppBar(
        selectedRoom: widget.selectedRoom,
        rooms: widget.rooms,
        onRoomChanged: widget.onRoomChanged,
        assetLogoPath: 'assets/images/VaCiam.png',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('rooms')
              .doc(widget.selectedRoom)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Text("Error loading air quality data",
                  style: TextStyle(color: Colors.red));
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text("No air quality data found for this room.",
                  style: TextStyle(color: Colors.red));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // AQI Summary Card (First)
                _buildAQICardWithMetrics(data),
                const SizedBox(height: 20),
                
                // Health Recommendations (Second)
                _buildHealthRecommendations(data),
                const SizedBox(height: 20),
                
                // Recent Readings Table (Third)
                _buildHistoricalDataTable(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Merged AQI + Current Metrics Card
Widget _buildAQICardWithMetrics(Map<String, dynamic> data) {
  // Composite AQI calculation
  Map<String, dynamic> aqiInfo = _calculateAQI(data);

  // Sensor values with safe fallbacks
  double pm25 = (data['pm25'] ?? 0).toDouble();
  String voc = data['voc']?.toString() ?? '-';
  String nox = data['nox']?.toString() ?? '-';
  String humidity = data['humidity']?.toString() ?? '-';
  String temperature = data['temperature']?.toString() ?? '-';

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          (aqiInfo['color'] ?? Colors.grey),
          (aqiInfo['color'] ?? Colors.grey).withOpacity(0.7)
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: (aqiInfo['color'] ?? Colors.grey).withOpacity(0.3),
          blurRadius: 15,
          offset: const Offset(0, 5),
        )
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // AQI Number
        Text(
          '${aqiInfo['aqi'] ?? 0}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Category Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            aqiInfo['category'] ?? 'Unknown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // AQI Description
        Text(
          aqiInfo['description'] ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),

        // Sensor Data in two columns
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PM2.5: $pm25 μg/m³',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'VOC: $voc ppb',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
            // Right Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOx: $nox ppb',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Humidity: $humidity%',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Temperature: $temperature°C',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

  // Historical Data Table - UPDATED with date filter
  Widget _buildHistoricalDataTable() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Readings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            Row(
              children: [
                // Export to Excel Button
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _exportToExcel, // NEW FUNCTION
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.download, size: 16, color: Color(0xFF2563EB)),
                            SizedBox(width: 6),
                            Text(
                              'Export',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Date Filter Button (existing)
                Container(
                  decoration: BoxDecoration(
                    color: _selectedDate != null 
                        ? const Color(0xFF8B5CF6).withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _showDatePicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: _selectedDate != null
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedDate != null
                                  ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                                  : 'Filter Date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedDate != null
                                    ? const Color(0xFF8B5CF6)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // (keep your Clear Filter + Show Less buttons below unchanged)
              ],
            ),
          ],
        ),
          const SizedBox(height: 16),
          _buildDataTable(),
        ],
      ),
    );
  }

  // NEW: Show date picker
  Future<void> _showDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF8B5CF6),
              onPrimary: Colors.white,
              onSurface: Color(0xFF111827),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _showAllReadings = false; // Reset view more when changing date
      });
    }
  }

// UPDATED: build recent reading with date filtering
Widget _buildDataTable() {
  if (widget.selectedRoom.isEmpty) {
    return const Center(child: Text("No room selected"));
  }

  // Build query based on whether a date is selected
  Query<Map<String, dynamic>> recentQuery;

  if (_selectedDate != null) {
    final startOfDay = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final endOfDay = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59, 59);

    recentQuery = FirebaseFirestore.instance
        .collection('sensor_history')
        .where('room', isEqualTo: widget.selectedRoom)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp', descending: true)
        .limit(100);
  } else {
    recentQuery = FirebaseFirestore.instance
        .collection('sensor_history')
        .where('room', isEqualTo: widget.selectedRoom)
        .orderBy('timestamp', descending: true)
        .limit(20);
  }

  return StreamBuilder<QuerySnapshot>(
    stream: recentQuery.snapshots(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
        );
      }

      if (snapshot.hasError) {
        return SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 32),
                const SizedBox(height: 8),
                const Text("Error loading recent readings"),
              ],
            ),
          ),
        );
      }

      final docs = snapshot.data?.docs ?? [];

      if (docs.isEmpty) {
        return SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, color: Colors.grey.shade400, size: 48),
                const SizedBox(height: 12),
                Text(
                  _selectedDate != null
                      ? "No readings for ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}"
                      : "No recent readings",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }

      final allReadings = docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;

        String formattedDateTime = "-";
        if (data['timestamp'] is Timestamp) {
          final localTime = (data['timestamp'] as Timestamp).toDate().toLocal();
          formattedDateTime = DateFormat('dd/MM/yyyy  hh:mm a').format(localTime);
        }

        return {
          'datetime': formattedDateTime,
          'pm25': (data['pm25'] ?? 0).toDouble(),
          'nox': (data['nox'] ?? 0).toDouble(),
          'voc': (data['voc'] ?? 0).toDouble(),
          'temp': (data['temperature'] ?? 0).toDouble(),
          'hum': (data['humidity'] ?? 0).toDouble(),
        };
      }).toList();

      final orderedReadings = allReadings; // already latest first
      final displayReadings = _showAllReadings ? orderedReadings : orderedReadings.take(5).toList();

      return Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 48,
              dataRowHeight: 56,
              columnSpacing: 24,
              headingRowColor: MaterialStateProperty.all(const Color(0xFFF9FAFB)),
              columns: const [
                DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                DataColumn(label: Text('PM2.5', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                DataColumn(label: Text('NOx', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                DataColumn(label: Text('VOC', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                DataColumn(label: Text('Temp', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                DataColumn(label: Text('Hum', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
              rows: displayReadings.map((r) {
                final pm25Color = _getPM25Color(r['pm25']);
                final noxValue = r['nox'] as double;
                Color noxColor;
                if (noxValue < 50) {
                  noxColor = const Color(0xFF16A34A);
                } else if (noxValue < 100) {
                  noxColor = const Color(0xFFFACC15);
                } else if (noxValue < 300) {
                  noxColor = const Color(0xFFF97316);
                } else {
                  noxColor = const Color(0xFFDC2626);
                }

                final vocValue = r['voc'] as double;
                Color vocColor;
                String vocStatus;
                if (vocValue < 250) {
                  vocColor = const Color(0xFF10B981);
                  vocStatus = 'Good';
                } else if (vocValue < 1000) {
                  vocColor = const Color(0xFFF59E0B);
                  vocStatus = 'Moderate';
                } else if (vocValue < 3000) {
                  vocColor = const Color(0xFFF97316);
                  vocStatus = 'Poor';
                } else {
                  vocColor = const Color(0xFFDC2626);
                  vocStatus = 'Critical';
                }

                return DataRow(cells: [
                  DataCell(Text(r['datetime'].toString(), style: const TextStyle(fontSize: 13))),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: pm25Color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${r['pm25']} μg/m³', style: TextStyle(color: pm25Color, fontWeight: FontWeight.w500, fontSize: 13)),
                  )),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: noxColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(noxValue.toStringAsFixed(1), style: TextStyle(color: noxColor, fontWeight: FontWeight.w600, fontSize: 13)),
                  )),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: vocColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${vocValue.toStringAsFixed(0)} ppb', style: TextStyle(color: vocColor, fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(vocStatus, style: TextStyle(color: vocColor, fontSize: 11)),
                      ],
                    ),
                  )),
                  DataCell(Text('${r['temp']}°C', style: const TextStyle(fontSize: 13))),
                  DataCell(Text('${r['hum']}%', style: const TextStyle(fontSize: 13))),
                ]);
              }).toList(),
            ),
          ),

          if (orderedReadings.length > 5 && !_showAllReadings)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAllReadings = true;
                    });
                  },
                  icon: const Icon(Icons.expand_more, size: 18, color: Color(0xFF8B5CF6)),
                  label: Text('View More (${orderedReadings.length - 5} more)', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

  // Health Recommendations based on composite AQI
  Widget _buildHealthRecommendations(Map<String, dynamic> data) {
    final aqiInfo = _calculateAQI(data);
    final category = aqiInfo['category'] ?? 'Unknown';

    List<Map<String, dynamic>> recommendations;

    switch (category) {
      case 'Good':
        recommendations = [
          {
            'icon': Icons.check_circle,
            'text': 'Air quality is excellent. Perfect time for outdoor activities.',
            'color': const Color(0xFF10B981),
          },
          {
            'icon': Icons.directions_walk,
            'text': 'Safe for all groups to be active outdoors.',
            'color': const Color(0xFF10B981),
          },
        ];
        break;

      case 'Moderate':
        recommendations = [
          {
            'icon': Icons.warning_amber,
            'text': 'Unusually sensitive people should consider reducing prolonged outdoor exertion.',
            'color': const Color(0xFFF59E0B),
          },
          {
            'icon': Icons.window,
            'text': 'Ventilate indoor spaces when possible.',
            'color': const Color(0xFFF59E0B),
          },
        ];
        break;

      case 'Unhealthy for Sensitive Groups':
        recommendations = [
          {
            'icon': Icons.masks,
            'text': 'Sensitive groups should limit outdoor activities.',
            'color': const Color(0xFFF97316),
          },
          {
            'icon': Icons.home,
            'text': 'Consider staying indoors with clean air circulation.',
            'color': const Color(0xFFF97316),
          },
        ];
        break;

      case 'Hazardous':
        recommendations = [
          {
            'icon': Icons.masks,
            'text': 'Everyone should avoid outdoor exertion.',
            'color': const Color(0xFFEF4444),
          },
          {
            'icon': Icons.home,
            'text': 'Stay indoors and use air purifiers if available.',
            'color': const Color(0xFFEF4444),
          },
          {
            'icon': Icons.warning,
            'text': 'Sensitive groups must remain indoors and avoid exposure.',
            'color': const Color(0xFFEF4444),
          },
        ];
        break;

      default:
        recommendations = [
          {
            'icon': Icons.info,
            'text': 'No specific recommendations available.',
            'color': Colors.grey,
          },
        ];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.health_and_safety,
                  color: Color(0xFF8B5CF6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Health Recommendations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...recommendations.map((rec) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: rec['color'].withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        rec['icon'],
                        size: 16,
                        color: rec['color'],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        rec['text'],
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // Helper Methods
Map<String, dynamic> _calculateAQI(Map<String, dynamic> data) {
   return CompositeAQI.evaluate(
     pm25: (data['pm25'] ?? 0).toDouble(),
     nox: (data['nox'] ?? 0).toDouble(),
   );
}

  Color _getPM25Color(double pm25) {
    if (pm25 <= 12) return const Color(0xFF10B981);
    if (pm25 <= 35.4) return const Color(0xFFF59E0B);
    if (pm25 <= 55.4) return const Color(0xFFEF4444);
    return const Color(0xFF991B1B);
  }

  List<Map<String, dynamic>> _getRecommendations(double pm25) {
    if (pm25 <= 12) {
      return [
        {
          'icon': Icons.check_circle,
          'text': 'Air quality is excellent. Perfect time for outdoor activities.',
          'color': const Color(0xFF10B981),
        },
        {
          'icon': Icons.directions_walk,
          'text': 'Safe for all groups to be active outdoors.',
          'color': const Color(0xFF10B981),
        },
      ];
    } else if (pm25 <= 35.4) {
      return [
        {
          'icon': Icons.warning_amber,
          'text': 'Unusually sensitive people should consider reducing prolonged outdoor exertion.',
          'color': const Color(0xFFF59E0B),
        },
        {
          'icon': Icons.window,
          'text': 'Keep windows open for ventilation.',
          'color': const Color(0xFFF59E0B),
        },
      ];
    } else {
      return [
        {
          'icon': Icons.masks,
          'text': 'Consider wearing a mask when outdoors.',
          'color': const Color(0xFFEF4444),
        },
        {
          'icon': Icons.window,
          'text': 'Keep windows closed and use air purifier.',
          'color': const Color(0xFFEF4444),
        },
        {
          'icon': Icons.home,
          'text': 'Sensitive groups should avoid outdoor activities.',
          'color': const Color(0xFFEF4444),
        },
      ];
    }
  }
  Future<void> _exportToExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Readings'];

      // Header row
      sheet.appendRow([
        TextCellValue('Date & Time'),
        TextCellValue('PM2.5'),
        TextCellValue('NOx'),
        TextCellValue('VOC'),
        TextCellValue('Temp'),
        TextCellValue('Hum'),
      ]);

      // Query Firestore
      final docs = await FirebaseFirestore.instance
          .collection('sensor_history')
          .where('room', isEqualTo: widget.selectedRoom)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      for (var doc in docs.docs) {
        final data = doc.data();
        String formattedDateTime = "-";
        if (data['timestamp'] is Timestamp) {
          final localTime = (data['timestamp'] as Timestamp).toDate().toLocal();
          formattedDateTime =
              DateFormat('dd/MM/yyyy hh:mm a').format(localTime);
        }

        sheet.appendRow([
          TextCellValue(formattedDateTime),
          DoubleCellValue((data['pm25'] ?? 0).toDouble()),
          DoubleCellValue((data['nox'] ?? 0).toDouble()),
          DoubleCellValue((data['voc'] ?? 0).toDouble()),
          DoubleCellValue((data['temperature'] ?? 0).toDouble()),
          DoubleCellValue((data['humidity'] ?? 0).toDouble()),
        ]);
      }

      // Save file
      final dir = await getDownloadsDirectory();
      final filePath = "${dir!.path}/recent_readings.xlsx";
      final fileBytes = excel.save();
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes!);

      // Auto-open file
      await OpenFilex.open(filePath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Exported and opened: $filePath"),
          backgroundColor: const Color(0xFF2563EB),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Export failed: $e"),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }
}