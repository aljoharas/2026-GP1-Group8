import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/game_provider.dart';
import 'providers/home_provider.dart';
import 'providers/logged_games_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/auth/login_screen.dart';


void main()async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LoadoutApp());
}

class LoadoutApp extends StatelessWidget {
  const LoadoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
        ChangeNotifierProvider(create: (_) => LoggedGamesProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
      ],
      child: MaterialApp(
        title: 'Loadout',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF0E0E12),
          colorScheme: const ColorScheme.dark(primary: Color(0xFF4ADE80)),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
