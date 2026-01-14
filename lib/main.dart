import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vaciam/services/alert_listener.dart';
import 'package:vaciam/services/notification.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/air_quality_screen.dart';
import 'screens/settings_screen.dart';

Future<void> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  print("🔹 Notification permission status: $status"); // debug
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();
  await requestNotificationPermission();

  runApp(const SmokeGuardApp());
}

class SmokeGuardApp extends StatelessWidget {
  const SmokeGuardApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmokeGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        fontFamily: 'Inter',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      setState(() {
        _user = user;
        _loading = false;
      });

      // ✅ Start AlertListener **only after user is authenticated**
      if (user != null) {
        AlertListener.start();
        debugPrint("🔹 AlertListener started after login");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return const LoginScreen();
    }

    return const DynamicHomeWrapper();
  }
}

/// Dynamic HomeWrapper that fetches rooms from Firestore
class DynamicHomeWrapper extends StatefulWidget {
  const DynamicHomeWrapper({Key? key}) : super(key: key);

  @override
  State<DynamicHomeWrapper> createState() => _DynamicHomeWrapperState();
}

class _DynamicHomeWrapperState extends State<DynamicHomeWrapper> {
  int _currentIndex = 0;

  List<String> _rooms = [];
  String? _selectedRoom;
  bool _loadingRooms = true;

  @override
  void initState() {
    super.initState();
    fetchRooms();
  }

  /// Fetch all rooms from Firestore
  Future<void> fetchRooms() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('rooms').get();
      final roomList = snapshot.docs.map((doc) => doc.id).toList();
      setState(() {
        _rooms = roomList;
        _selectedRoom = roomList.isNotEmpty ? roomList.first : null;
        _loadingRooms = false;
      });
      debugPrint("✅ Rooms fetched from Firestore: $_rooms");
    } catch (e) {
      debugPrint("❌ Error fetching rooms: $e");
      setState(() => _loadingRooms = false);
    }
  }

  void _updateSelectedRoom(String room) {
    setState(() => _selectedRoom = room);
    debugPrint("🔹 Selected room changed to: $room");
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRooms || _selectedRoom == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Widget> _screens = [
      DashboardScreen(
        selectedRoom: _selectedRoom!,
        rooms: _rooms,
        onRoomChanged: _updateSelectedRoom,
      ),
      AlertsScreen(
        selectedRoom: _selectedRoom!,
        rooms: _rooms,
        onRoomChanged: _updateSelectedRoom,
      ),
      AirQualityScreen(
        selectedRoom: _selectedRoom!,
        rooms: _rooms,
        onRoomChanged: _updateSelectedRoom,
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.air_outlined),
            activeIcon: Icon(Icons.air),
            label: 'Air Quality',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
