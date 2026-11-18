import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../core/theme.dart';
import '../../providers/app_state.dart';
import '../../services/api_client.dart';
import '../../widgets/common.dart';
import '../reports/reports_page.dart';

const _site = 'ws_saadiyat_tower';
const _crew = 'crew_concrete_a';
const _json = {'worksite_id': _site};

/// Guided five-minute hackathon demo: talk track + one-click actions.
class DemoController extends ChangeNotifier {
  bool open = false;
  int step = 0;
  bool busy = false;
  final Set<int> done = {};

  void toggle() {
    open = !open;
    if (!open) crewId = null;
    notifyListeners();
  }

  void goTo(int i) {
    step = i;
    notifyListeners();
  }

  /// Crew assessment docked next to the guide (non-modal, so the guide stays usable).
  String? crewId;

  void showCrew(String id) {
    crewId = id;
    notifyListeners();
  }

  void hideCrew() {
    crewId = null;
    notifyListeners();
  }

  void setBusy(bool v) {
    busy = v;
    notifyListeners();
  }

  void complete(int i, int total) {
    done.add(i);
    if (i < total - 1) step = i + 1;
    notifyListeners();
  }
}

class DemoStep {
  const DemoStep(this.title, this.say, this.button, this.run, {this.showsCrew = false});
  final bool showsCrew; // keeps the docked crew assessment visible
  final String title;
  final String say; // talk track for the presenter
  final String button;
  final Future<void> Function(BuildContext context, ApiClient api, NavController nav) run;
}

Future<void> _steps(ApiClient api, int n) async {
  for (var i = 0; i < n; i++) {
    await api.post('/simulation/step');
  }
}

String? _openHeatAlert(AppState s) {
  for (final a in s.alerts) {
    if (a.crewId == _crew && a.type == 'heat_risk' && !a.resolved) return a.id;
  }
  return null;
}

final demoSteps = <DemoStep>[
  DemoStep(
    'Prepare a clean demo',
    'Resets the simulation, clears history and builds 30 minutes of simulated readings at the Saadiyat Island tower site.',
    'Prepare',
    (ctx, api, nav) async {
      await api.post('/simulation/reset', {'clear_history': true});
      await api.post('/simulation/scenario', {'worksite_id': _site, 'scenario_id': 'normal'});
      await api.put('/crews/$_crew', {'acclimatization': 'acclimatized', 'workload': 'heavy', 'work_rest_regime': 'continuous'});
      await api.post('/simulation/speed', {'speed': 1});
      await api.post('/simulation/start');
      await _steps(api, 30);
      nav.go(Nav.overview);
    },
  ),
  DemoStep(
    'Introduce the site',
    '"This is a simulated construction site on Saadiyat Island, Abu Dhabi, with one virtual heat-stress station. '
        'It is a November morning, the cool season. Everything is labelled as simulated, and every number comes from the backend."',
    'Show overview',
    (ctx, api, nav) async => nav.go(Nav.overview),
  ),
  DemoStep(
    'Show live conditions',
    '"The station measures air, wet-bulb and globe temperature. HeatGuard combines them into WBGT, the standard heat-stress index, '
        'using the outdoor formula because the site is in direct sun."',
    'Open live monitoring',
    (ctx, api, nav) async => nav.go(Nav.monitoring),
  ),
  DemoStep(
    'Select a crew doing heavy work',
    '"Concrete Crew A is doing heavy work. Because they are acclimatized, NIOSH\'s exposure limit applies. Today they are within it."',
    'Open Concrete Crew A',
    (ctx, api, nav) async {
      nav.go(Nav.overview);
      if (ctx.mounted) ctx.read<DemoController>().showCrew(_crew);
    },
    showsCrew: true,
  ),
  DemoStep(
    'Change acclimatization',
    '"Suppose half the crew are new to the site. For unacclimatized workers NIOSH sets a lower alert limit, so the same heat is now a concern, '
        'and the explanation says exactly why."',
    'Set "not acclimatized"',
    (ctx, api, nav) async {
      await api.put('/crews/$_crew', {'acclimatization': 'not_acclimatized'});
      if (ctx.mounted) ctx.read<DemoController>().showCrew(_crew);
    },
    showsCrew: true,
  ),
  DemoStep(
    'Increase the heat',
    '"Now the day heats up: +4 °C and stronger sun. Watch the level rise. HeatGuard tells us which work/rest schedule is needed to stay within the limit."',
    'Raise heat',
    (ctx, api, nav) async {
      await api.post('/simulation/adjust', {..._json, 'tdb_offset': 4, 'solar_scale': 1.3});
      await _steps(api, 3);
      if (ctx.mounted) ctx.read<DemoController>().showCrew(_crew);
    },
    showsCrew: true,
  ),
  DemoStep(
    'A protective alert is raised',
    '"An alert is generated automatically, with the explanation and recommended actions. Repeats are suppressed, and alerts are never cleared automatically."',
    'Open alerts',
    (ctx, api, nav) async => nav.go(Nav.alerts),
  ),
  DemoStep(
    'Acknowledge the alert',
    '"The supervisor acknowledges it. If nobody does, it escalates."',
    'Acknowledge Crew A alert',
    (ctx, api, nav) async {
      final s = ctx.read<AppState>();
      await s.refresh();
      final id = _openHeatAlert(s);
      if (id != null) await api.post('/alerts/$id/acknowledge', {'supervisor_id': 'supervisor-demo'});
      nav.go(Nav.alerts);
    },
  ),
  DemoStep(
    'Record an intervention',
    '"We record the protective action: a 15 min work / 45 min rest rotation and lighter tasks. The crew is reassessed immediately, and the level drops."',
    'Record rotation',
    (ctx, api, nav) async {
      final s = ctx.read<AppState>();
      await s.refresh();
      await api.post('/interventions', {
        'alert_id': _openHeatAlert(s),
        'crew_id': _crew,
        'action': 'work_rotation',
        'new_work_rest_regime': '15_45',
        'new_workload': 'moderate',
        'notes': 'Rotation started; shaded rest area at the level-4 stair core.',
      });
      nav.go(Nav.interventions);
    },
  ),
  DemoStep(
    'Trigger a sensor failure',
    '"Now the globe sensor fails. HeatGuard does not guess and does not show green. It marks the assessment as unavailable, '
        'shows the last valid result as history, and raises a data alert."',
    'Break the globe sensor',
    (ctx, api, nav) async {
      await api.post('/simulation/sensor-failure', {..._json, 'sensor': 'globe', 'mode': 'missing'});
      await _steps(api, 1);
      nav.go(Nav.monitoring);
    },
  ),
  DemoStep(
    'Restore the sensor',
    '"When the sensor comes back, assessments resume. The earlier alert stays open until a supervisor reviews it."',
    'Restore',
    (ctx, api, nav) async {
      await api.post('/simulation/sensor-restore', _json);
      await _steps(api, 1);
    },
  ),
  DemoStep(
    'UAE midday break',
    '"Summer in Abu Dhabi: we jump to 12:35 on a July day. Besides the heat-stress level, HeatGuard checks the UAE midday break: '
        'outdoor work in direct sun is not permitted from 12:30 to 15:00, 15 June to 15 September. It raises a separate compliance alert."',
    'Jump to 12:35 in July',
    (ctx, api, nav) async {
      await api.post('/simulation/scenario', {'worksite_id': _site, 'scenario_id': 'increasing_heat'});
      await api.post('/simulation/jump', {'worksite_id': _site, 'sim_clock': '12:35'});
      nav.go(Nav.alerts);
    },
  ),
  DemoStep(
    'Show the evaluation',
    '"Finally, we test HeatGuard on 8 repeatable synthetic scenarios against ground truth: early warning, no missed alerts, '
        'and zero minutes showing safe while data were missing. This is software verification, not clinical validation."',
    'Run evaluation',
    (ctx, api, nav) async {
      await api.post('/evaluation/run');
      ReportsPage.tab.value = 1;
      ReportsPage.reload.value++;
      nav.go(Nav.reports);
    },
  ),
  DemoStep(
    'Worker view',
    '"Workers see only their crew\'s notice in plain language: water, rest and emergency guidance. No tracking and no individual data."',
    'Open worker view',
    (ctx, api, nav) async => Navigator.of(ctx).pushNamed('/worker'),
  ),
];

class DemoPanel extends StatelessWidget {
  const DemoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<DemoController>();
    final t = Theme.of(context).textTheme;
    return Container(
      width: 360,
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: HG.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 12),
          child: Row(children: [
            const Icon(Icons.slideshow_outlined, color: HG.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Demo guide', style: t.titleMedium)),
            Text('${demo.step + 1} / ${demoSteps.length}', style: t.bodySmall),
            IconButton(tooltip: 'Close guide', icon: const Icon(Icons.close), onPressed: demo.toggle),
          ]),
        ),
        LinearProgressIndicator(value: (demo.step + 1) / demoSteps.length, minHeight: 3, backgroundColor: HG.subtle),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: demoSteps.length,
            itemBuilder: (context, i) => _StepTile(index: i),
          ),
        ),
      ]),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<DemoController>();
    final step = demoSteps[index];
    final current = demo.step == index;
    final isDone = demo.done.contains(index);
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => demo.goTo(index),
      child: Container(
        color: current ? const Color(0xFFF5F8FF) : null,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDone ? HG.routine : (current ? HG.primary : HG.subtle),
              shape: BoxShape.circle,
            ),
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text('${index + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: current ? Colors.white : HG.text)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: t.titleSmall?.copyWith(color: current || isDone ? HG.text : HG.muted)),
              if (current) ...[
                const SizedBox(height: 6),
                Text(step.say, style: t.bodyMedium?.copyWith(color: HG.muted, height: 1.5)),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton(
                    onPressed: demo.busy ? null : () => _run(context, demo),
                    child: demo.busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(step.button),
                  ),
                  const SizedBox(width: 8),
                  if (index < demoSteps.length - 1) TextButton(onPressed: () => demo.goTo(index + 1), child: const Text('Skip')),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _run(BuildContext context, DemoController demo) async {
    final state = context.read<AppState>();
    final nav = context.read<NavController>();
    demo.setBusy(true);
    if (!demoSteps[index].showsCrew) demo.hideCrew();
    String? error;
    try {
      await demoSteps[index].run(context, state.api, nav);
      await state.refresh();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    demo.setBusy(false);
    if (error == null) demo.complete(index, demoSteps.length);
    if (error != null && context.mounted) showResult(context, error, '');
  }
}
