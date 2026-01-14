import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/app_bar_widget.dart';
import '../models/alert_model.dart';

enum TimeRange { today, week, month }

enum DetectionType { none, cigarette, vape, both }

class HeatmapData {
  final int count;
  final DetectionType type;
  
  HeatmapData(this.count, this.type);
}

class DayDetectionData {
  final DateTime date;
  final int count;
  final DetectionType type;
  final String peakTime;
  
  DayDetectionData({
    required this.date,
    required this.count,
    required this.type,
    required this.peakTime,
  });
}

class AnalysisResult {
  final String peakTime;
  final String mostFrequentDay;
  final String suggestedAction;
  final String detectedTypes;
  final Map<String, int> detectionBreakdown;
  
  AnalysisResult({
    required this.peakTime,
    required this.mostFrequentDay,
    required this.suggestedAction,
    required this.detectedTypes,
    required this.detectionBreakdown,
  });
}

class AlertsScreen extends StatefulWidget {
  final String selectedRoom;
  final List<String>? rooms;
  final Function(String)? onRoomChanged;

  const AlertsScreen({
    Key? key,
    required this.selectedRoom,
    this.rooms,
    this.onRoomChanged,
  }) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _showAllAlerts = false;
  bool _isAnalyzing = false;
  AnalysisResult? _analysisResult;
  DateTime _selectedMonth = DateTime.now();
  Map<String, DayDetectionData> _calendarData = {};
  
  // Search functionality state (date only)
  DateTime? _searchDate;
  bool _isSearching = false;
  final TextEditingController _searchTextController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _searchTextController.addListener(_onSearchTextChanged);
  }
  
  @override
  void dispose() {
    _searchTextController.dispose();
    super.dispose();
  }
  
  void _onSearchTextChanged() {
    if (_searchTextController.text.isEmpty) {
      setState(() {
        _isSearching = false;
      });
    }
  }

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('alerts')
            .where('room', isEqualTo: widget.selectedRoom)
            .orderBy('time', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    "Error loading alerts",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }
          
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final alertDocs = snapshot.data!.docs;
          final alerts = alertDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return AlertModel(
              id: doc.id,
              room: data['room'] ?? 'Unknown',
              type: data['type'] ?? 'Unknown Alert',
              time: (data['time'] as Timestamp?)?.toDate().toString() ?? 'Unknown',
              status: _statusFromString(data['status'] ?? 'resolved'),
              imageUrl: data['image_url'],
              pm25: data['pm25'],
              co2: data['co2'],
              temperature: data['temperature'],
              humidity: data['humidity'],
            );
          }).toList();

          // Filter alerts based on search date
          List<AlertModel> filteredAlerts = alerts;
          if (_isSearching && _searchDate != null) {
            filteredAlerts = alerts.where((alert) {
              try {
                final alertTime = DateTime.parse(alert.time);
                // Compare only year, month, and day
                return alertTime.year == _searchDate!.year &&
                       alertTime.month == _searchDate!.month &&
                       alertTime.day == _searchDate!.day;
              } catch (e) {
                return false;
              }
            }).toList();
          }

          // Process calendar data
          _calendarData = _processCalendarData(alertDocs);

          // Limit alerts to show
          final displayedAlerts = _showAllAlerts ? filteredAlerts : filteredAlerts.take(4).toList();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                
                // Calendar Heatmap Card
                _buildCalendarHeatmapCard(alertDocs),
                
                const SizedBox(height: 20),
                
                // Analyze Button
                _buildAnalyzeButton(alertDocs),
                
                // Analysis Results
                if (_analysisResult != null) ...[
                  const SizedBox(height: 20),
                  _buildAnalysisResults(),
                ],
                
                const SizedBox(height: 24),
                
                // Alerts List Section with Search Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left side: Title and count
                      Row(
                        children: [
                          Text(
                            _isSearching ? 'Search Results' : 'Recent Alerts',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isSearching ? const Color(0xFFDBEAFE) : const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _isSearching ? '${filteredAlerts.length}' : '${alerts.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isSearching ? const Color(0xFF2563EB) : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          if (_isSearching) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _clearSearch,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.clear, size: 12, color: Color(0xFFDC2626)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Clear',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      
                      // Right side: Search Icon Button
                      Container(
                        decoration: BoxDecoration(
                          color: _isSearching ? const Color(0xFF2563EB) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isSearching ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB),
                          ),
                          boxShadow: _isSearching 
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF2563EB).withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 20,
                                  color: _isSearching ? Colors.white : const Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isSearching ? 'Filtered' : 'Search',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _isSearching ? Colors.white : const Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Search indicator when active
                if (_isSearching && _searchDate != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Showing alerts from: ${DateFormat('MMMM dd, yyyy').format(_searchDate!)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _clearSearch,
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                if (filteredAlerts.isEmpty)
                  _buildEmptyState(_isSearching)
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: displayedAlerts.map((alert) => _buildAlertCard(alert)).toList(),
                    ),
                  ),
                  
                  // View All / Show Less Button
                  if (filteredAlerts.length > 4)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showAllAlerts = !_showAllAlerts;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _showAllAlerts ? 'Show Less' : 'View All Alerts (${filteredAlerts.length})',
                                style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _showAllAlerts ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                color: const Color(0xFF2563EB),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  // Date picker function (date only)
  Future<void> _pickDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _searchDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Search alerts by date',
      cancelText: 'Cancel',
      confirmText: 'Search',
      fieldLabelText: 'Date',
      fieldHintText: 'MM/DD/YYYY',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    
    if (pickedDate != null) {
      setState(() {
        _searchDate = pickedDate;
        _isSearching = true;
      });
    }
  }

  // Clear search function
  void _clearSearch() {
    setState(() {
      _searchDate = null;
      _isSearching = false;
    });
  }

  AlertStatus _statusFromString(String status) {
    switch (status.toLowerCase()) {
      case 'critical':
        return AlertStatus.critical;
      case 'warning':
        return AlertStatus.warning;
      default:
        return AlertStatus.resolved;
    }
  }

  Widget _buildCalendarHeatmapCard(List<QueryDocumentSnapshot> alerts) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      Icons.calendar_month,
                      color: Color(0xFF2563EB),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Calendar',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedMonth),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Color(0xFF6B7280)),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month - 1,
                        );
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = DateTime(
                          _selectedMonth.year,
                          _selectedMonth.month + 1,
                        );
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Calendar Grid
          _buildCalendarGrid(),
          
          const SizedBox(height: 20),
          
          // Legend
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startingWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday
    final daysInMonth = lastDayOfMonth.day;

    return Column(
      children: [
        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        
        // Calendar days
        ...List.generate(6, (weekIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (dayIndex) {
                final dayNumber = weekIndex * 7 + dayIndex - startingWeekday + 1;
                
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return Expanded(child: Container());
                }
                
                final date = DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber);
                final dateKey = DateFormat('yyyy-MM-dd').format(date);
                final dayData = _calendarData[dateKey];
                
                return Expanded(
                  child: GestureDetector(
                    onTap: dayData != null && dayData.count > 0
                        ? () => _showDayDetailsModal(dayData)
                        : null,
                    child: _buildCalendarDay(dayNumber, dayData),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCalendarDay(int day, DayDetectionData? data) {
    Color cellColor;
    Color borderColor;
    double opacity = 0.3;
    
    if (data == null || data.count == 0) {
      cellColor = const Color(0xFFF3F4F6);
      borderColor = const Color(0xFFE5E7EB);
    } else {
      switch (data.type) {
        case DetectionType.cigarette:
          cellColor = const Color(0xFFEF4444);
          borderColor = const Color(0xFFDC2626);
          break;
        case DetectionType.vape:
          cellColor = const Color(0xFF3B82F6);
          borderColor = const Color(0xFF2563EB);
          break;
        case DetectionType.both:
          cellColor = const Color(0xFF8B5CF6);
          borderColor = const Color(0xFF7C3AED);
          break;
        default:
          cellColor = const Color(0xFFF3F4F6);
          borderColor = const Color(0xFFE5E7EB);
      }
      
      // Calculate opacity based on count (1-10+ scale)
      opacity = (data.count / 10).clamp(0.4, 1.0);
      cellColor = cellColor.withOpacity(opacity);
    }
    
    final isToday = DateTime.now().year == data?.date.year &&
                    DateTime.now().month == data?.date.month &&
                    DateTime.now().day == day;
    
    return Container(
      height: 45,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: cellColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday ? const Color(0xFF2563EB) : borderColor,
          width: isToday ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day.toString(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: data != null && data.count > 0
                    ? Colors.white
                    : const Color(0xFF6B7280),
              ),
            ),
            if (data != null && data.count > 0) ...[
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, DayDetectionData> _processCalendarData(List<QueryDocumentSnapshot> alerts) {
    final Map<String, Map<String, dynamic>> dailyData = {};
    
    for (var doc in alerts) {
      try {
        final alertData = doc.data() as Map<String, dynamic>;
        final timestamp = (alertData['time'] as Timestamp).toDate();
        final type = (alertData['type'] ?? '').toString().toLowerCase();
        
        // Only process alerts from selected month
        if (timestamp.year != _selectedMonth.year || 
            timestamp.month != _selectedMonth.month) {
          continue;
        }
        
        DetectionType detectionType;
        if (type.contains('cigarette') || type.contains('smoke')) {
          detectionType = DetectionType.cigarette;
        } else if (type.contains('vape') || type.contains('vapor')) {
          detectionType = DetectionType.vape;
        } else {
          continue;
        }
        
        final dateKey = DateFormat('yyyy-MM-dd').format(timestamp);
        
        if (!dailyData.containsKey(dateKey)) {
          dailyData[dateKey] = {
            'date': timestamp,
            'count': 0,
            'cigarettes': 0,
            'vapes': 0,
            'hours': <int, int>{},
          };
        }
        
        dailyData[dateKey]!['count'] = (dailyData[dateKey]!['count'] as int) + 1;
        
        if (detectionType == DetectionType.cigarette) {
          dailyData[dateKey]!['cigarettes'] = (dailyData[dateKey]!['cigarettes'] as int) + 1;
        } else {
          dailyData[dateKey]!['vapes'] = (dailyData[dateKey]!['vapes'] as int) + 1;
        }
        
        // Track hour counts
        final hour = timestamp.hour;
        final hourCounts = dailyData[dateKey]!['hours'] as Map<int, int>;
        hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        
      } catch (e) {
        // Skip invalid entries
      }
    }
    
    // Convert to DayDetectionData
    final Map<String, DayDetectionData> result = {};
    
    dailyData.forEach((dateKey, data) {
      final cigarettes = data['cigarettes'] as int;
      final vapes = data['vapes'] as int;
      
      DetectionType type;
      if (cigarettes > 0 && vapes > 0) {
        type = DetectionType.both;
      } else if (cigarettes > 0) {
        type = DetectionType.cigarette;
      } else {
        type = DetectionType.vape;
      }
      
      // Find peak hour
      final hourCounts = data['hours'] as Map<int, int>;
      String peakTime = 'N/A';
      if (hourCounts.isNotEmpty) {
        final peakHour = hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        final endHour = (peakHour + 2) % 24;
        peakTime = '${peakHour.toString().padLeft(2, '0')}:00–${endHour.toString().padLeft(2, '0')}:00';
      }
      
      result[dateKey] = DayDetectionData(
        date: data['date'] as DateTime,
        count: data['count'] as int,
        type: type,
        peakTime: peakTime,
      );
    });
    
    return result;
  }

  void _showDayDetailsModal(DayDetectionData data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Date header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getTypeColor(data.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      color: _getTypeColor(data.type),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d').format(data.date),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      Text(
                        DateFormat('yyyy').format(data.date),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Detection count card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getTypeColor(data.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getTypeColor(data.type).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.show_chart,
                      color: _getTypeColor(data.type),
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Detections',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.count.toString(),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: _getTypeColor(data.type),
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(data.type),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getTypeLabel(data.type),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Peak time card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Color(0xFF6B7280),
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Most Common Time',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.peakTime,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Color _getTypeColor(DetectionType type) {
    switch (type) {
      case DetectionType.cigarette:
        return const Color(0xFFEF4444);
      case DetectionType.vape:
        return const Color(0xFF3B82F6);
      case DetectionType.both:
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  String _getTypeLabel(DetectionType type) {
    switch (type) {
      case DetectionType.cigarette:
        return 'Cigarette';
      case DetectionType.vape:
        return 'Vape';
      case DetectionType.both:
        return 'Both';
      default:
        return 'None';
    }
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Legend',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem('Cigarette', const Color(0xFFEF4444), Icons.smoking_rooms),
              _buildLegendItem('Vape', const Color(0xFF3B82F6), Icons.vaping_rooms),
              _buildLegendItem('Both', const Color(0xFF8B5CF6), Icons.warning),
            ],
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Darker colors = more detections',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

// SOLUTION: Remove the first _buildAnalyzeButton method (around line 562-595)
// and keep ONLY this updated version:

Widget _buildAnalyzeButton(List<QueryDocumentSnapshot> alerts) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isAnalyzing 
            ? null 
            : () {
                if (_analysisResult != null) {
                  // Close analysis
                  setState(() {
                    _analysisResult = null;
                  });
                } else {
                  // Perform analysis
                  _performAnalysis(alerts);
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: _analysisResult != null 
              ? const Color(0xFF6B7280) 
              : const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isAnalyzing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _analysisResult != null 
                        ? Icons.close 
                        : Icons.analytics, 
                    size: 20
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _analysisResult != null 
                        ? 'Close Analysis' 
                        : 'Analyze Detection Pattern',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}


  Future<void> _performAnalysis(List<QueryDocumentSnapshot> alerts) async {
    setState(() {
      _isAnalyzing = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    final result = _analyzeData(alerts);

    setState(() {
      _isAnalyzing = false;
      _analysisResult = result;
    });
  }

  AnalysisResult _analyzeData(List<QueryDocumentSnapshot> alerts) {
    final Map<String, int> hourCounts = {};
    final Map<String, int> dayCounts = {};
    int cigaretteCount = 0;
    int vapeCount = 0;

    for (var doc in alerts) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = (data['time'] as Timestamp).toDate();
        final type = (data['type'] ?? '').toString().toLowerCase();

        if (timestamp.year != _selectedMonth.year || 
            timestamp.month != _selectedMonth.month) {
          continue;
        }

        if (type.contains('cigarette') || type.contains('smoke')) {
          cigaretteCount++;
        } else if (type.contains('vape') || type.contains('vapor')) {
          vapeCount++;
        }

        final hour = timestamp.hour;
        final hourKey = '$hour:00';
        hourCounts[hourKey] = (hourCounts[hourKey] ?? 0) + 1;

        final day = DateFormat('EEEE').format(timestamp);
        dayCounts[day] = (dayCounts[day] ?? 0) + 1;
      } catch (e) {
        // Skip invalid entries
      }
    }

    String peakTime = 'No detections';
    if (hourCounts.isNotEmpty) {
      final maxHour = hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      peakTime = maxHour.key;
    }

    String mostFrequentDay = 'No data';
    if (dayCounts.isNotEmpty) {
      final maxDay = dayCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      mostFrequentDay = maxDay.key;
    }

    String detectedTypes;
    if (cigaretteCount > 0 && vapeCount > 0) {
      detectedTypes = 'Both cigarettes and vapes';
    } else if (cigaretteCount > 0) {
      detectedTypes = 'Cigarettes only';
    } else if (vapeCount > 0) {
      detectedTypes = 'Vapes only';
    } else {
      detectedTypes = 'No detections';
    }

    String suggestedAction;
    final totalDetections = cigaretteCount + vapeCount;
    if (totalDetections > 20) {
      suggestedAction = 'Immediate intervention required. Consider installing additional monitoring and implementing stricter policies.';
    } else if (totalDetections > 10) {
      suggestedAction = 'Moderate activity detected. Increase patrol frequency during peak times and conduct awareness sessions.';
    } else if (totalDetections > 0) {
      suggestedAction = 'Low activity detected. Monitor the situation and maintain current prevention measures.';
    } else {
      suggestedAction = 'No violations detected. Continue current monitoring practices.';
    }

    return AnalysisResult(
      peakTime: peakTime,
      mostFrequentDay: mostFrequentDay,
      suggestedAction: suggestedAction,
      detectedTypes: detectedTypes,
      detectionBreakdown: {
        'Cigarettes': cigaretteCount,
        'Vapes': vapeCount,
      },
    );
  }

  Widget _buildAnalysisResults() {
    if (_analysisResult == null) return const SizedBox();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
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
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.assessment,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Analysis Summary',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          _buildSummaryCard(
            'Peak Detection Time',
            _analysisResult!.peakTime,
            Icons.schedule,
            const Color(0xFFEF4444),
          ),
          
          const SizedBox(height: 12),
          
          _buildSummaryCard(
            'Most Frequent Day',
            _analysisResult!.mostFrequentDay,
            Icons.calendar_today,
            const Color(0xFF3B82F6),
          ),
          
          const SizedBox(height: 12),
          
          _buildSummaryCard(
            'Detection Types',
            _analysisResult!.detectedTypes,
            Icons.smoke_free,
            const Color(0xFF8B5CF6),
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Detection Breakdown',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                ..._analysisResult!.detectionBreakdown.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: entry.key == 'Cigarettes'
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            entry.value.toString(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Suggested Action',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _analysisResult!.suggestedAction,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                          height: 1.4,
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

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.darken(0.3),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color.darken(0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isSearching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearching ? Icons.search_off : Icons.notifications_none,
                size: 64,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearching ? 'No alerts found' : 'No alerts yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching 
                  ? 'No alerts on ${_searchDate != null ? DateFormat('MMMM dd, yyyy').format(_searchDate!) : 'selected date'}'
                  : 'All systems are running normally',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton(
                  onPressed: _clearSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Clear Filter'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(AlertModel alert) {
    Color statusColor;
    Color statusBgColor;
    IconData statusIcon;
    
    switch (alert.status) {
      case AlertStatus.critical:
        statusColor = const Color(0xFFEF4444);
        statusBgColor = const Color(0xFFFEE2E2);
        statusIcon = Icons.error;
        break;
      case AlertStatus.warning:
        statusColor = const Color(0xFFF59E0B);
        statusBgColor = const Color(0xFFFEF3C7);
        statusIcon = Icons.warning_amber;
        break;
      default:
        statusColor = const Color(0xFF10B981);
        statusBgColor = const Color(0xFFD1FAE5);
        statusIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          title: Text(
            alert.type,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Color(0xFF111827),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  _formatTime(alert.time),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: Colors.grey[400],
          ),
          children: [
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 16),
            
            if (alert.imageUrl != null && alert.imageUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  alert.imageUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(Icons.image_not_supported, color: Colors.grey[400]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (alert.pm25 != null || alert.co2 != null || 
                alert.temperature != null || alert.humidity != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sensor Readings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (alert.pm25 != null)
                          Expanded(child: _buildMetricChip('PM2.5', alert.pm25.toString(), 'μg/m³', Icons.blur_on)),
                        if (alert.pm25 != null && alert.co2 != null) const SizedBox(width: 8),
                        if (alert.co2 != null)
                          Expanded(child: _buildMetricChip('CO₂', alert.co2.toString(), 'ppm', Icons.cloud)),
                      ],
                    ),
                    if ((alert.pm25 != null || alert.co2 != null) && 
                        (alert.temperature != null || alert.humidity != null))
                      const SizedBox(height: 8),
                    Row(
                      children: [
                        if (alert.temperature != null)
                          Expanded(child: _buildMetricChip('Temp', alert.temperature.toString(), '°C', Icons.thermostat)),
                        if (alert.temperature != null && alert.humidity != null) const SizedBox(width: 8),
                        if (alert.humidity != null)
                          Expanded(child: _buildMetricChip('Humidity', alert.humidity.toString(), '%', Icons.water_drop)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, String unit, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeString) {
    try {
      final dateTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM dd, yyyy').format(dateTime);
      }
    } catch (e) {
      return timeString;
    }
  }
}

extension ColorExtension on Color {
  Color darken(double amount) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }
}