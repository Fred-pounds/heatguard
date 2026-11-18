import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../features/alerts/alerts_page.dart';
import '../features/crews/crews_page.dart';
import '../features/demo/demo_guide.dart';
import '../features/health/worker_health_page.dart';
import '../features/planner/shift_plan_page.dart';
import '../services/worker_link.dart';
import '../features/interventions/interventions_page.dart';
import '../features/monitoring/monitoring_page.dart';
import '../features/overview/overview_page.dart';
import '../features/reports/reports_page.dart';
import '../features/settings/settings_page.dart';
import '../features/simulation/simulation_lab_page.dart';
import '../providers/app_state.dart';
import '../widgets/assessment_dialog.dart';
import '../widgets/common.dart';

class NavController extends ChangeNotifier {
  int index = 0;
  void go(int i) {
    index = i;
    notifyListeners();
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.subtitle, {this.group});
  final String label;
  final IconData icon;
  final String subtitle;
  final String? group;
}

const _items = [
  _NavItem('Overview', Icons.space_dashboard_outlined, 'What needs your attention right now', group: 'Monitor'),
  _NavItem('Live Monitoring', Icons.thermostat_outlined, 'Current conditions and crew assessments'),
  _NavItem('Alerts', Icons.notifications_none_rounded, 'Acknowledge and act on alerts', group: 'Act'),
  _NavItem('Interventions', Icons.healing_outlined, 'Protective actions taken and their effect'),
  _NavItem('Shift plan', Icons.event_note_outlined, 'Plan heavy tasks, rotation and breaks for the rest of the shift'),
  _NavItem('Worker health', Icons.monitor_heart_outlined, 'Consented wearable signals and symptom escalations'),
  _NavItem('Crews', Icons.groups_outlined, 'Work context used for each assessment', group: 'Manage'),
  _NavItem('Simulation Lab', Icons.science_outlined, 'Drive the simulated sensing station'),
  _NavItem('Reports', Icons.insert_chart_outlined, 'Performance, evaluation and exports'),
  _NavItem('Settings', Icons.tune_rounded, 'Methodology, governance and configuration'),
];

// Indices used for in-app navigation
class Nav {
  static const overview = 0, monitoring = 1, alerts = 2, interventions = 3, plan = 4, health = 5, crews = 6, lab = 7, reports = 8, settings = 9;
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  static const pages = <Widget>[
    OverviewPage(),
    MonitoringPage(),
    AlertsPage(),
    InterventionsPage(),
    ShiftPlanPage(),
    WorkerHealthPage(),
    CrewsPage(),
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
                    opacity: state.dataIsLive ? 1 : 0.5,
                    child: IndexedStack(index: nav.index, children: pages),
                  ),
      ),
    ]);
    final demo = context.watch<DemoController>();
    final main = demo.open
        ? Row(children: [
            Expanded(child: body),
            if (demo.crewId != null)
              Container(
                width: 460,
                decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: HG.border))),
                child: CrewAssessmentSheet(crewId: demo.crewId!, onClose: demo.hideCrew),
              ),
            const DemoPanel(),
          ])
        : body;
    return Scaffold(
      drawer: wide ? null : const Drawer(width: 248, backgroundColor: HG.navy, child: _Sidebar()),
      body: wide ? Row(children: [const SizedBox(width: 232, child: _Sidebar()), Expanded(child: main)]) : main,
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
    final dbOk = '${health['database_status']}' == 'ok';
    final sensorsOk = state.worksites.every((w) => w.sensorStatus == 'ok');
    final allOk = state.dataIsLive && dbOk && sensorsOk && state.simulation['state'] == 'running';
    return Container(
      color: HG.navy,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: HG.accent, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('HeatGuard', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (_items[i].group != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, i == 0 ? 0 : 18, 12, 6),
                    child: Text(_items[i].group!.toUpperCase(),
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  ),
                _NavTile(
                  item: _items[i],
                  selected: nav.index == i,
                  badge: i == Nav.alerts && unack > 0
                      ? '$unack'
                      : (i == Nav.health && state.openEscalations.isNotEmpty ? '${state.openEscalations.length}' : null),
                  onTap: () {
                    nav.go(i);
                    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.pop(context);
                  },
                ),
              ],
            ]),
          ),
          Tooltip(
            message: 'Backend: ${state.dataIsLive ? 'online' : 'unavailable'}\n'
                'Database: ${humanize('${health['database_backend'] ?? '-'}')} (${health['database_status'] ?? '-'})\n'
                'Simulator: ${state.simulation['state'] ?? '-'}\n'
                'Sensors: ${state.worksites.map((w) => '${w.name.split(' ').first} ${w.sensorStatus}').join(', ')}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 20, 20),
              child: StatusDot(allOk ? 'ok' : (state.dataIsLive ? 'degraded' : 'offline'),
                  label: allOk
                      ? 'All systems normal'
                      : !state.dataIsLive
                          ? 'Backend unavailable'
                          : !sensorsOk
                              ? 'Sensor problem'
                              : 'Partially degraded',
                  dark: true),
            ),
          ),
        ]),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap, this.badge});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? HG.navy2 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(item.icon, size: 19, color: selected ? Colors.white : Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, fontSize: 14)),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: HG.high, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
      );
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
      height: 72,
      padding: EdgeInsets.fromLTRB(showMenu ? 8 : 32, 0, narrow ? 8 : 24, 0),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: HG.border))),
      child: Row(children: [
        if (showMenu) IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer()),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.label, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
            if (!narrow) Text(item.subtitle, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (!narrow) ...[const SimulatedBadge(), const SizedBox(width: 12)],
        Builder(builder: (context) {
          final demo = context.watch<DemoController>();
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: demo.open
                ? FilledButton.tonalIcon(onPressed: demo.toggle, icon: const Icon(Icons.slideshow_outlined, size: 18), label: const Text('Demo guide'))
                : OutlinedButton.icon(onPressed: demo.toggle, icon: const Icon(Icons.slideshow_outlined, size: 18), label: const Text('Demo guide')),
          );
        }),
        if (state.worksites.isNotEmpty && !narrow)
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: state.selectedWorksite?.id,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(Icons.expand_more, size: 18),
              style: const TextStyle(fontSize: 14, color: HG.text, fontWeight: FontWeight.w500),
              items: [
                for (final w in state.worksites)
                  DropdownMenuItem(
                    value: w.id,
                    child: Row(children: [
                      Icon(w.environment == 'indoor' ? Icons.factory_outlined : Icons.location_on_outlined, size: 17, color: HG.muted),
                      const SizedBox(width: 8),
                      Text(w.name),
                    ]),
                  ),
              ],
              onChanged: state.selectWorksite,
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: unack == 0 ? 'No unacknowledged alerts' : '$unack unacknowledged alert(s)',
          onPressed: () => nav.go(Nav.alerts),
          icon: Badge(isLabelVisible: unack > 0, label: Text('$unack'), backgroundColor: HG.high, child: const Icon(Icons.notifications_none_rounded)),
        ),
        PopupMenuButton<String>(
          tooltip: 'Account',
          icon: CircleAvatar(radius: 15, backgroundColor: state.isOhs ? const Color(0xFFDCEFEA) : HG.subtle, child: Text(state.isOhs ? 'OH' : 'SV', style: const TextStyle(color: HG.text, fontSize: 11.5, fontWeight: FontWeight.w600))),
          onSelected: (v) {
            if (v == 'worker') openWorkerApp();
            if (v == 'settings') nav.go(Nav.settings);
            if (v == 'role') state.setRole(state.isOhs ? 'supervisor' : 'ohs');
          },
          itemBuilder: (_) => [
            PopupMenuItem(enabled: false, child: Text(state.isOhs ? 'OHS officer (demo role)' : 'Site Supervisor (demo role)')),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'role', child: Text(state.isOhs ? 'Switch to supervisor' : 'Switch to OHS role (health data)')),
            const PopupMenuItem(value: 'worker', child: Text('Open worker app (new tab)')),
            const PopupMenuItem(value: 'settings', child: Text('Methodology & governance')),
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
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: HG.high, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Connection to HeatGuard lost. Information shown was last updated '
            '${state.lastSuccess == null ? 'never' : ago(state.lastSuccess!.toUtc().toIso8601String())} and is not live.',
            style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        OutlinedButton(onPressed: state.refresh, child: const Text('Retry')),
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: HG.muted),
          const SizedBox(height: 16),
          Text('HeatGuard service unavailable', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'The dashboard cannot reach ${state.api.baseUrl}. No heat-risk information is shown, because stale data is never displayed as live.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HG.muted),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: state.refresh, child: const Text('Try again')),
        ]),
      ),
    );
  }
}
