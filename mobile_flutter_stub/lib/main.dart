import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'navigation/app_shell.dart';
import 'screens/agent_setup_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';
import 'screens/meeting_screen.dart';
import 'screens/profile_screen.dart';
import 'services/session_state.dart';
import 'theme/premium_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionState.instance.loadLocalPreferences();
  runApp(const KaihuiBarApp());
}

class KaihuiBarApp extends StatelessWidget {
  const KaihuiBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
            GoRoute(path: '/meetings', builder: (context, state) => const MeetingScreen()),
            GoRoute(path: '/friends', builder: (context, state) => const FriendsScreen()),
            GoRoute(path: '/agents', builder: (context, state) => const AgentSetupScreen()),
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: '开会吧',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildPremiumTheme(),
    );
  }
}
