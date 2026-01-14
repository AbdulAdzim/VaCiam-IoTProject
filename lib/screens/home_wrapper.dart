import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_screen.dart';

class HomeWrapper extends StatefulWidget {
  const HomeWrapper({Key? key}) : super(key: key);

  @override
  State<HomeWrapper> createState() => _HomeWrapperState();
}

class _HomeWrapperState extends State<HomeWrapper> {
  String? _selectedRoom;
  List<String> _rooms = [];

  @override
  void initState() {
    super.initState();
    fetchRooms();
  }

  /// Fetch all room document IDs from Firestore
  Future<void> fetchRooms() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('rooms').get();
      final roomList = snapshot.docs.map((doc) => doc.id).toList();
      if (roomList.isEmpty) {
        debugPrint("⚠️ No rooms found in Firestore!");
      } else {
        debugPrint("✅ Rooms fetched from Firestore: $roomList");
      }
      setState(() {
        _rooms = roomList;
        _selectedRoom = roomList.isNotEmpty ? roomList.first : null;
      });
    } catch (e) {
      debugPrint("❌ Error fetching rooms: $e");
    }
  }

  /// Called when user selects a new room
  void _updateSelectedRoom(String room) {
    setState(() {
      _selectedRoom = room;
    });
    debugPrint("🔹 Selected room changed to: $room");
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedRoom == null) {
      // Show loading spinner while rooms are being fetched
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DashboardScreen(
      selectedRoom: _selectedRoom!,
      rooms: _rooms,
      onRoomChanged: _updateSelectedRoom,
    );
  }
}
