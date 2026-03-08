import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      body: child,
      bottomNavigationBar: BottomNavigationBar(
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
    );
  }
}
