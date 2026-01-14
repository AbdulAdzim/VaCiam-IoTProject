import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/sensor_model.dart';
import 'info_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// state variables for available sensors
List<String> _availableSensors = [];
String? _selectedSensorId;

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _sensorIdController = TextEditingController();
  final _roomNameController = TextEditingController();
  bool _isToggleCooldown = false;
  List<SensorModel> _sensors = [];

  @override
  void initState() {
    super.initState();
    _loadAuthProfile();
    _fetchSensors();
  }

  void _loadAuthProfile() {
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() {
      _emailController.text = user.email ?? '';
    });
  }

Future<void> _fetchSensors() async {
  try {
    final response = await http.get(Uri.parse('http://10.123.2.119:5000/sensors'));
    print("🔍 GET /sensors status: ${response.statusCode}");
    print("🔍 Raw body: ${response.body}");
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      final List<dynamic> sensorsData = data['sensors'] ?? [];
      print("🔍 Parsed sensors: $sensorsData");
      setState(() {
        _sensors = sensorsData.map((item) {
          return SensorModel(
            id: item['sensor_id'] ?? 'Unknown',
            room: item['room'] ?? 'Unknown',
            isActive: item['is_active'] ?? true,
            isConnected: item['status'] == 'online',
          );
        }).toList();

        _availableSensors = sensorsData .map<String>((item) => item['sensor_id'] as String) .toList();
                print("🔍 Available sensors for dropdown: $_availableSensors");
              });
            }
  } catch (e) {
    print('❌ Error fetching sensors: $e');
  }
}

  Future<void> _toggleSensor(String sensorId, bool isActive) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.123.2.119:5000/sensors/$sensorId/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'is_active': isActive}),
      );

      if (response.statusCode == 200) {
        print('Sensor $sensorId toggled successfully');
      } else {
        print('Failed to toggle sensor: ${response.body}');
      }
    } catch (e) {
      print('Error toggling sensor: $e');
    }
  }

  void _showAddSensorDialog() {
    _sensorIdController.clear();
    _roomNameController.clear();
    _selectedSensorId = null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add New Sensor',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                const SizedBox(height: 24),
                const Text('Sensor ID',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedSensorId,
                  items: _availableSensors.map((id) {
                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(id),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSensorId = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Select online sensor',
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Room Name',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                const SizedBox(height: 8),
                TextField(
                  controller: _roomNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Room 204',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (_selectedSensorId != null && _roomNameController.text.isNotEmpty) {
                          try {
                            final response = await http.post(
                              Uri.parse('http://10.123.2.119:5000/add_sensor'),
                              headers: {'Content-Type': 'application/json'},
                              body: json.encode({
                                'sensor_id': _selectedSensorId,
                                'room': _roomNameController.text,
                              }),
                            );
                            if (response.statusCode == 200) {
                              await _fetchSensors();
                              if (mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sensor added successfully'),
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed: ${response.body}'),
                                  backgroundColor: const Color(0xFFEF4444),
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          content: const Text('Are you sure you want to logout?', style: TextStyle(color: Color(0xFF6B7280))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      try {
        await _auth.signOut();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error logging out: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }
  @override
  void dispose() {
    _emailController.dispose();
    _sensorIdController.dispose();
    _roomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assignedSensors = _sensors
  .where((sensor) => sensor.room != null && sensor.room != 'Unknown' && sensor.isConnected)
  .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset('assets/images/VaCiam.png', height: 28, fit: BoxFit.contain),
            const SizedBox(width: 8),
            const Text('Settings',
                style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w600, fontSize: 20)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // PROFILE SECTION
            _buildSection(
              title: 'Profile',
              children: [
                _buildInfoTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: _emailController.text,
                ),
                _buildActionTile(
                  icon: Icons.lock_outline,
                  title: 'Password',
                  subtitle: '••••••••',
                  onTap: () async {
                    final user = _auth.currentUser;
                    if (user?.email != null) {
                      await _auth.sendPasswordResetEmail(email: user!.email!);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password reset email sent')),
                        );
                      }
                    }
                  },
                  trailing: const Text('Change',
                      style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            // Then build the section
            _buildSection(
              title: 'Sensors',
              trailing: InkWell(
                onTap: _showAddSensorDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Add',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              children: assignedSensors.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text('No sensors added yet',
                              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                        ),
                      ),
                    ]
                  : List.generate(assignedSensors.length, (index) {
                      final sensor = assignedSensors[index];
                      return _buildSensorTile(sensor, index);
                    }),
            ),
            // APP INFO SECTION
            _buildSection(
              title: 'App Info',
              children: [
                _buildActionTile(
                  icon: Icons.info_outline,
                  title: 'Version',
                  subtitle: '1.0.0',
                  onTap: null,
                ),
                _buildActionTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                      builder: (context) => InfoPage(
                        title: "Privacy Policy",
                        sections: [
                          Text("Privacy Policy", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 12),
                          Text("VaCiam is committed to protecting your privacy. This policy explains how we collect, use, and safeguard your information.",
                              style: TextStyle(fontSize: 16, height: 1.5)),
                          SizedBox(height: 20),
                          Text("Information We Collect", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("- Account details (email address)\n- Sensor data (PM2.5, VOC, NOx, humidity, temperature)\n- Room assignments and usage logs",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),
                          Text("Data Sharing", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("- We do not sell or rent your personal information\n- Data may be shared with trusted providers (Firebase, hosting)",
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      ),
                    );
                  },
                ),
              ],
            ),

            // SUPPORT SECTION
            _buildSection(
              title: 'Support',
              children: [
                _buildActionTile(
                  icon: Icons.help_outline,
                  title: 'FAQ',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                      builder: (context) => InfoPage(
                        title: "FAQ",
                        sections: [
                          Text("Frequently Asked Questions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 12),
                          Text("Here are answers to common questions about VaCiam.", style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),
                          Text("What is AQI?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("AQI (Air Quality Index) is a standardized measure of air pollution. VaCiam calculates AQI using EPA guidelines for PM2.5 and NO₂.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),
                          Text("How do I add a sensor?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("Go to Settings → Sensors → Add. Select an available sensor ID and assign it to a room.",
                              style: TextStyle(fontSize: 16)),
                          Text("Frequently Asked Questions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 12),
                          Text("Here are answers to common questions about VaCiam.", style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("What do the AQI colors mean?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("Green = Good (0–50)\nYellow = Moderate (51–100)\nOrange = Unhealthy for Sensitive Groups (101–150)\nRed = Unhealthy (151–200)\nPurple = Very Unhealthy (201–300)\nBrown = Hazardous (301–500)",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("What is VOC?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("VOC stands for Volatile Organic Compounds. These are gases emitted from products like paints, cleaning supplies, or smoke. High VOC levels can cause irritation or health issues indoors.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("What is NOx?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("NOx refers to nitrogen oxides, a group of gases produced mainly from combustion (vehicles, cigarettes, vapes). They contribute to smog and respiratory problems.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("Why do I see both raw values and AQI?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("Raw values show the actual sensor reading. AQI converts those readings into a standardized scale (0–500) so you can easily understand health impact.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("Why does the app sometimes show 'Unknown' for a sensor?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("This means the sensor is online but hasn’t been assigned to a room yet. You can assign it in Settings → Sensors → Add.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("How does the app detect cigarette or vape smoke?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("The system uses PM2.5 and VOC patterns to classify smoke events. Alerts are logged in the Detection Summary.",
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),

                          Text("Why are humidity and temperature shown separately?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("Humidity and temperature don’t affect AQI directly, but they are displayed as comfort indicators to help you understand indoor conditions.",
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      ),
                    );
                  },
                ),
                _buildActionTile(
                  icon: Icons.email_outlined,
                  title: 'Contact Support',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                      builder: (context) => InfoPage(
                        title: "Contact Support",
                        sections: [
                          Text("Contact Support", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 12),
                          Text("If you experience issues or have questions, please reach out:", style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),
                          Text("Email", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("support@vaciam.com", style: TextStyle(fontSize: 16)),
                          SizedBox(height: 20),
                          Text("Response Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text("We aim to respond within 48 hours.", style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      ),
                    );
                  },
                ),
              ],
            ),

            // LOGOUT BUTTON
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.logout, size: 20),
                      SizedBox(width: 8),
                      Text('Logout',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, Widget? trailing, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              if (trailing != null) trailing,
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              final index = entry.key;
              final child = entry.value;
              return Column(
                children: [
                  if (index > 0) const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  child,
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
      {required IconData icon, required String title, String? subtitle, VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Color(0xFF6B7280)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ],
              ),
            ),
            trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)) : const SizedBox()),
          ],
        ),
      ),
    );
  }
  Widget _buildSensorTile(SensorModel sensor, int index) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.sensors, size: 20, color: Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sensor.room,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(sensor.id, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ],
            ),
          ),
          Switch(
            value: sensor.isActive,
            onChanged: (value) async {
              if (_isToggleCooldown) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Please wait before toggling again"),
                    backgroundColor: Color(0xFFEF4444),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              setState(() => _sensors[index].isActive = value);

              _isToggleCooldown = true;
              await _toggleSensor(sensor.id, value);

              // Show in-app notification
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value ? "Sensor turned ON" : "Sensor turned OFF"),
                  backgroundColor: value ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  duration: const Duration(seconds: 2),
                ),
              );

              Future.delayed(const Duration(seconds: 3), () {
                setState(() {
                  _isToggleCooldown = false;
                });
              });
            },
            activeColor: const Color(0xFF10B981),
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
