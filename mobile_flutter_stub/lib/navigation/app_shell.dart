import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    ('/home', Icons.home_outlined, Icons.home, '首页'),
    ('/meetings', Icons.forum_outlined, Icons.forum, '会议'),
    ('/friends', Icons.group_outlined, Icons.group, '好友'),
    ('/agents', Icons.smart_toy_outlined, Icons.smart_toy, '智能体'),
    ('/profile', Icons.person_outline, Icons.person, '我的'),
  ];

  int _indexOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexOf(location);

    return Scaffold(
      extendBody: true, // Let body extend behind bottom nav
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey(location),
          child: child,
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Theme.of(context).bottomNavigationBarTheme.backgroundColor?.withValues(alpha: 0.8) ??
                Colors.white.withValues(alpha: 0.8),
            child: BottomNavigationBar(
              elevation: 0,
              backgroundColor: Colors.transparent, // Let Container handle color and opacity
              currentIndex: currentIndex,
              onTap: (index) => context.go(_tabs[index].$1),
              items: [
                for (final tab in _tabs)
                  BottomNavigationBarItem(
                    icon: Icon(tab.$2),
                    activeIcon: Icon(tab.$3),
                    label: tab.$4,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
