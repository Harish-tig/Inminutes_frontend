import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/user_screen.dart';
import 'state/shop_state.dart';
import 'state/user_state.dart';
import 'utils/app_theme.dart';
import 'widgets/state_views.dart';

void main() {
  runApp(const InMinutesApp());
}

/// App root. Two notifiers live for the whole app; `GroupState` is created per
/// group session instead (see `GroupScreen.route`).
class InMinutesApp extends StatelessWidget {
  const InMinutesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserState()..restore()),
        ChangeNotifierProvider(create: (_) => ShopState()),
      ],
      child: MaterialApp(
        title: 'InMinutes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const _Root(),
      ),
    );
  }
}

/// Shows the create-user screen until a user exists, then the home screen.
/// Only this small widget listens to `UserState`, so nothing else rebuilds.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return Consumer<UserState>(
      builder: (context, userState, _) {
        if (userState.loading) {
          return const Scaffold(
            body: LoadingView(message: 'Starting up...'),
          );
        }
        return userState.hasUser ? const HomeScreen() : const UserScreen();
      },
    );
  }
}
