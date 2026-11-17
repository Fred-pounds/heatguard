import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../features/alerts/alerts_page.dart';
import '../features/crews/crews_page.dart';
import '../features/interventions/interventions_page.dart';
import '../features/monitoring/monitoring_page.dart';
import '../features/overview/overview_page.dart';
import '../features/reports/reports_page.dart';
import '../features/settings/settings_page.dart';
import '../features/simulation/simulation_lab_page.dart';
import '../providers/app_state.dart';
import '../widgets/common.dart';

class NavController extends ChangeNotifier {
  int index = 0;
  void go(int i) {
    index = i;
    notifyListeners();
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.subtitle);
  final String label;
  final IconData icon;
  final String subtitle;
}

const _items = [
  _NavItem('Overview', Icons.dashboard_outlined, 'Site-wide heat-risk situation'),
  _NavItem('Live Monitoring', Icons.monitor_heart_outlined, 'Environmental readings and crew assessments'),
  _NavItem('Crew Management', Icons.groups_outlined, 'Crew work context used by the assessment'),
  _NavItem('Alerts', Icons.notifications_active_outlined, 'Acknowledge, act on and resolve alerts'),
  _NavItem('Interventions', Icons.healing_outlined, 'Documented protective actions and follow-up'),
  _NavItem('Simulation Lab', Icons.science_outlined, 'Drive the simulated sensing station'),
  _NavItem('Reports', Icons.insights_outlined, 'Metrics, evaluation and CSV export'),
  _NavItem('Settings', Icons.tune_outlined, 'Methodology, governance and configuration'),
];

class Shell extends StatelessWidget {
  const Shell({super.key});

  static const pages = <Widget>[
    OverviewPage(),
    MonitoringPage(),
    CrewsPage(),
    AlertsPage(),
    InterventionsPage(),
    SimulationLabPage(),
    ReportsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final state = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final body = Column(children: [
      _Header(item: _items[nav.index], showMenu: !wide),
      if (!state.dataIsLive && state.initialised) const _OfflineBanner(),
      Expanded(
        child: !state.initialised
            ? const LoadingState()
            : (state.worksites.isEmpty && !state.backendOnline)
                ? const _ServiceUnavailable()
                : Opacity(
                    // stale data is visibly de-emphasised, never shown as live
                    opacity: state.dataIsLive ? 1 : 0.55,
                    child: IndexedStack(index: nav.index, children: pages),
                  ),
      ),
    ]);
    return Scaffold(
      drawer: wide ? null : const Drawer(width: 250, backgroundColor: HG.navy, child: _Sidebar()),
      body: wide ? Row(children: [const SizedBox(width: 240, child: _Sidebar()), Expanded(child: body)]) : body,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();
  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final state = context.watch<AppState>();
    final unack = (state.counts['unacknowledged_alerts'] as num?)?.toInt() ?? 0;
    final health = state.health;
    return Container(
      color: HG.navy,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF59F00), Color(0xFFE8590C)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('HeatGuard', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                Text('Heat-risk early warning', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ]),
          ),
          const Divider(color: HG.navyLine),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: nav.index == i ? HG.navy2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        nav.go(i);
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          Icon(_items[i].icon, size: 19, color: nav.index == i ? const Color(0xFFFFA94D) : Colors.white60),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(_items[i].label,
                                style: TextStyle(
                                    color: nav.index == i ? Colors.white : Colors.white70,
                                    fontWeight: nav.index == i ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 13.5)),
                          ),
                          if (i == 3 && unack > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(color: HG.high, borderRadius: BorderRadius.circular(10)),
                              child: Text('$unack', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: HG.navy2, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SYSTEM STATUS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              StatusDot(state.dataIsLive ? 'ok' : 'offline', label: state.dataIsLive ? 'Backend online' : 'Backend unavailable', dark: true),
              const SizedBox(height: 5),
              StatusDot(
                  '${health['database_status'] ?? 'unknown'}',
                  label: 'Database: ${humanize(health['database_backend'] as String? ?? '-')}'
                      '${((health['pending_sync_writes'] as num?) ?? 0) > 50 ? ' (${health['pending_sync_writes']} unsynced)' : ''}',
                  dark: true),
              const SizedBox(height: 5),
              StatusDot('${state.simulation['state'] ?? 'unknown'}', label: 'Simulator ${state.simulation['state'] ?? '-'}', dark: true),
            ]),
          ),
          const Divider(color: HG.navyLine),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(children: [
              CircleAvatar(radius: 16, backgroundColor: Color(0xFF2B4A73), child: Text('SV', style: TextStyle(color: Colors.white, fontSize: 12))),
              SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Site Supervisor', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Demo role · crew-level access', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.showMenu});
  final _NavItem item;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final nav = context.read<NavController>();
    final unack = (state.counts['unacknowledged_alerts'] as num?)?.toInt() ?? 0;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Container(
      padding: EdgeInsets.fromLTRB(showMenu ? 6 : 24, 12, narrow ? 8 : 20, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: HG.border))),
      child: Row(children: [
        if (showMenu) IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer()),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(item.label, style: Theme.of(context).textTheme.headlineSmall, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              const SimulatedBadge(text: 'SIMULATED DATA'),
            ]),
            if (!narrow)
              Text('${item.subtitle} · ${DateFormat('EEEE d MMMM yyyy').format(DateTime.now())}',
                  style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (state.worksites.isNotEmpty && !narrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(border: Border.all(color: HG.border), borderRadius: BorderRadius.circular(8)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: state.selectedWorksite?.id,
                icon: const Icon(Icons.expand_more, size: 18),
                style: const TextStyle(fontSize: 13, color: HG.text, fontWeight: FontWeight.w600),
                items: [
                  for (final w in state.worksites)
                    DropdownMenuItem(
                      value: w.id,
                      child: Row(children: [
                        Icon(w.environment == 'indoor' ? Icons.factory_outlined : Icons.construction, size: 16, color: HG.muted),
                        const SizedBox(width: 8),
                        Text(w.name),
                      ]),
                    ),
                ],
                onChanged: state.selectWorksite,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Tooltip(
          message: '$unack unacknowledged alert(s)',
          child: IconButton(
            onPressed: () => nav.go(3),
            icon: Badge(
              isLabelVisible: unack > 0,
              label: Text('$unack'),
              backgroundColor: HG.high,
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'User menu',
          icon: const CircleAvatar(radius: 15, backgroundColor: HG.navy, child: Text('SV', style: TextStyle(color: Colors.white, fontSize: 11))),
          onSelected: (v) {
            if (v == 'worker') Navigator.of(context).pushNamed('/worker');
            if (v == 'settings') nav.go(7);
            if (v == 'refresh') state.refresh();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(enabled: false, child: Text('Signed in as Site Supervisor (demo role)')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'worker', child: ListTile(dense: true, leading: Icon(Icons.phone_android), title: Text('Open worker view'))),
            PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.policy_outlined), title: Text('Methodology & governance'))),
            PopupMenuItem(value: 'refresh', child: ListTile(dense: true, leading: Icon(Icons.refresh), title: Text('Refresh now'))),
          ],
        ),
      ]),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      width: double.infinity,
      color: HG.high,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(children: [
        const Icon(Icons.cloud_off, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Cannot reach the HeatGuard service. Information below was last updated '
            '${state.lastSuccess == null ? 'never' : ago(state.lastSuccess!.toUtc().toIso8601String())} and is NOT live - do not treat it as current.',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ),
        TextButton(onPressed: state.refresh, child: const Text('Retry', style: TextStyle(color: Colors.white))),
      ]),
    );
  }
}

class _ServiceUnavailable extends StatelessWidget {
  const _ServiceUnavailable();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SectionCard(
          child: Column(children: [
            const Icon(Icons.cloud_off, size: 48, color: HG.high),
            const SizedBox(height: 10),
            Text('HeatGuard service unavailable', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'The dashboard cannot reach the backend (${state.api.baseUrl}). No heat-risk information is shown because '
              'HeatGuard never displays stale data as live. Start the backend and retry.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(state.lastError ?? '', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: state.refresh, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ]),
        ),
      ),
    );
  }
}
