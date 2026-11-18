import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app/shell.dart';
import 'core/theme.dart';
import 'features/demo/demo_guide.dart';
import 'features/worker/worker_page.dart';
import 'providers/app_state.dart';

void main() {
  runApp(const HeatGuardApp());
}

class HeatGuardApp extends StatelessWidget {
  const HeatGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..start()),
        ChangeNotifierProvider(create: (_) => NavController()),
        ChangeNotifierProvider(create: (_) => DemoController()),
      ],
      child: MaterialApp(
        title: 'HeatGuard',
        debugShowCheckedModeBanner: false,
        theme: HG.theme(),
        initialRoute: '/',
        onGenerateRoute: (settings) {
          final name = settings.name ?? '/';
          if (name.startsWith('/worker')) {
            return MaterialPageRoute(settings: settings, builder: (_) => const WorkerPage());
          }
          return MaterialPageRoute(settings: settings, builder: (_) => const Shell());
        },
      ),
    );
  }
}
