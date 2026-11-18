import 'package:flutter/material.dart';

import 'core/state.dart';
import 'core/theme.dart';
import 'ui/home.dart';
import 'ui/onboarding.dart';
import 'ui/widgets.dart';

/// HeatGuard Worker: the app workers carry with them (web, Android, iOS).
/// Separate from the supervisor dashboard; it talks to the same HeatGuard API with the worker role.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = WorkerState();
  runApp(WorkerApp(state: state));
  await state.init();
}

class WorkerApp extends StatelessWidget {
  const WorkerApp({super.key, required this.state});
  final WorkerState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'HeatGuard',
          debugShowCheckedModeBanner: false,
          theme: T.theme(),
          builder: (context, child) => Directionality(textDirection: state.l.isRtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
          home: !state.ready
              ? const Scaffold(body: Center(child: AppLogo(size: 64)))
              : state.onboarded
              ? const HomeScreen()
              : const OnboardingScreen(),
        ),
      ),
    );
  }
}
