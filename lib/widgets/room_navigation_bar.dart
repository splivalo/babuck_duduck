import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/config/room_ui_config.dart';
import '../models/app_models.dart';

class RoomNavigationBar extends StatefulWidget {
  const RoomNavigationBar({
    super.key,
    required this.currentRoom,
    required this.onRoomSelected,
  });

  final RoomId currentRoom;
  final ValueChanged<RoomId> onRoomSelected;

  @override
  State<RoomNavigationBar> createState() => _RoomNavigationBarState();
}

class _RoomNavigationBarState extends State<RoomNavigationBar> {
  bool _isOpen = false;

  void _toggleOpen() {
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  void _handleRoomSelected(RoomId room) {
    widget.onRoomSelected(room);
    setState(() {
      _isOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final roomButtons = roomNavigationItems
        .map((item) {
          final isSelected = widget.currentRoom == item.room;
          final uiConfig = roomButtonUiConfigMap[item.room]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RoomDrawerButton(
              config: item,
              uiConfig: uiConfig,
              isSelected: isSelected,
              onPressed: () => _handleRoomSelected(item.room),
            ),
          );
        })
        .toList(growable: false);

    return SizedBox(
      width: 88,
      child: Stack(
        alignment: Alignment.topRight,
        clipBehavior: Clip.none,
        children: <Widget>[
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            opacity: _isOpen ? 0 : 1,
            child: IgnorePointer(
              ignoring: _isOpen,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _RoomDrawerTrigger(
                  key: const ValueKey<String>('room-drawer-trigger-host'),
                  onPressed: _toggleOpen,
                ),
              ),
            ),
          ),
          AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            offset: _isOpen ? Offset.zero : const Offset(1.2, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              opacity: _isOpen ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_isOpen,
                child: SizedBox(
                  width: 76,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: roomButtons,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDrawerTrigger extends StatelessWidget {
  const _RoomDrawerTrigger({super.key, required this.onPressed});

  static const String _homeAssetPath = 'assets/ui/menu_home.png';

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('room-drawer-trigger'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Center(
            child: const _MenuGlyphAsset(
              assetPath: _homeAssetPath,
              fallbackIcon: Icons.home_rounded,
              size: 68,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomDrawerButton extends StatelessWidget {
  const _RoomDrawerButton({
    required this.config,
    required this.uiConfig,
    required this.isSelected,
    required this.onPressed,
  });

  final RoomConfig config;
  final RoomButtonUiConfig uiConfig;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('room-drawer-item-${config.room.name}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Center(
            child: _RoomIconGlyph(
              uiConfig: uiConfig,
              isSelected: isSelected,
              expandedStyle: true,
              highlightSelected: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomIconGlyph extends StatelessWidget {
  const _RoomIconGlyph({
    required this.uiConfig,
    required this.isSelected,
    required this.expandedStyle,
    required this.highlightSelected,
  });

  final RoomButtonUiConfig uiConfig;
  final bool isSelected;
  final bool expandedStyle;
  final bool highlightSelected;

  @override
  Widget build(BuildContext context) {
    final glyphSize = expandedStyle ? 68.0 : 60.0;
    final showSelectionOutline = isSelected && highlightSelected;

    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: showSelectionOutline ? 1.0 : 0.96,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        opacity: 1.0,
        child: SizedBox(
          width: glyphSize + 8,
          height: glyphSize + 8,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              _MenuGlyphAsset(
                assetPath: uiConfig.assetPath,
                fallbackIcon: uiConfig.mockIcon,
                size: glyphSize,
              ),
              if (showSelectionOutline)
                Container(
                  width: glyphSize + 6,
                  height: glyphSize + 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuGlyphAsset extends StatelessWidget {
  const _MenuGlyphAsset({
    required this.assetPath,
    required this.fallbackIcon,
    required this.size,
  });

  final String assetPath;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          Transform.translate(
            offset: const Offset(0, 2),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Opacity(
                opacity: 0.2,
                child: Image.asset(
                  assetPath,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  color: Colors.black,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      fallbackIcon,
                      size: size * 0.72,
                      color: Colors.black,
                    );
                  },
                ),
              ),
            ),
          ),
          Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                fallbackIcon,
                size: size * 0.72,
                color: const Color(0xFF7A6A56),
              );
            },
          ),
        ],
      ),
    );
  }
}
