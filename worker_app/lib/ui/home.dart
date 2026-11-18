import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import 'health.dart';
import 'help.dart';
import 'settings.dart';
import 'today.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    s.onAlert = (title, body) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body),
          ]),
        ));
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        toolbarHeight: 64,
        title: Row(children: [
          const AppLogo(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.crewName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(s.siteName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: T.muted)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: l.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: tab, children: const [TodayTab(), HealthTab(), HelpTab()]),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: T.border))),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), selectedIcon: const Icon(Icons.wb_sunny), label: l.t('tab_today')),
            NavigationDestination(icon: const Icon(Icons.favorite_border), selectedIcon: const Icon(Icons.favorite), label: l.t('tab_health')),
            NavigationDestination(icon: const Icon(Icons.local_hospital_outlined), selectedIcon: const Icon(Icons.local_hospital), label: l.t('tab_help')),
          ],
        ),
      ),
    );
  }
}
