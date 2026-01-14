class SensorModel {
  final String id;
  final String room;
  bool isActive;
  final bool isConnected;

  SensorModel({
    required this.id,
    required this.room,
    required this.isActive,
    required this.isConnected,
  });
}