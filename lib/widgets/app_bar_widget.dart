import 'package:flutter/material.dart';

typedef RoomChangedCallback = void Function(String room);

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? selectedRoom;
  final List<String>? rooms;
  final RoomChangedCallback? onRoomChanged;
  final double height;
  final String? assetLogoPath;

  const CustomAppBar({
    Key? key,
    this.selectedRoom,
    this.rooms,
    this.onRoomChanged,
    this.height = kToolbarHeight,
    this.assetLogoPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
  Widget logo = assetLogoPath != null
      ? SizedBox(
          height: 36,
          width: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Center(
                child: Image.asset(
                  assetLogoPath!,
                  height: 20,              // ✅ SAME feel as Settings page
                  fit: BoxFit.contain,     // ✅ no crop, no zoom
                ),
              ),
            ),
          ),
        )
      : const Icon(Icons.air, color: Color(0xFF2563EB));

    Widget roomWidget;
    if (rooms != null && onRoomChanged != null) {
      roomWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: PopupMenuButton<String>(
          initialValue: selectedRoom,
          onSelected: (room) => onRoomChanged!(room),
          itemBuilder: (context) => rooms!
              .map((room) => PopupMenuItem(
                    value: room,
                    child: Text(room),
                  ))
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedRoom ?? 'Select Room',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6B7280)),
            ],
          ),
        ),
      );
    } else {
      roomWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedRoom ?? 'Room',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF6B7280)),
          ],
        ),
      );
    }

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: Row(
        children: [
          logo,
          const SizedBox(width: 8),
          const Text(
            'VaCiam',
            style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Spacer(),
          roomWidget,
        ],
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
}
