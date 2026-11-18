import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/api_client.dart';
import '../../widgets/assessment_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/wbgt_chart.dart';
import '../crews/crews_page.dart' show acclIds, workloadIds;
import '../interventions/intervention_form.dart';

class SimulationLabPage extends StatefulWidget {
  const SimulationLabPage({super.key});
  @override
  State<SimulationLabPage> createState() => _SimulationLabPageState();
}

class _SimulationLabPageState extends State<SimulationLabPage> {
  String? crewId;
  double tdbOffset = 0, rhOffset = 0, solarScale = 1, windOffset = 0;
  bool ovTdb = false, ovTnwb = false, ovTg = false;
  double tdb = 32, tnwb = 26, tg = 42;
  String faultSensor = 'globe';
  String faultMode = 'missing';
  String? loadedFor;

  void _syncFromStation(AppState s, String wsId) {
    if (loadedFor == wsId) return;
    final st = s.stationStatus(wsId);
    if (st == null) return;
    final adj = jMap(st['adjustments']);
    tdbOffset = jNum(adj['tdb_offset']) ?? 0;
    rhOffset = jNum(adj['rh_offset']) ?? 0;
    solarScale = jNum(adj['solar_scale']) ?? 1;
    windOffset = jNum(adj['wind_offset']) ?? 0;
    final ov = jMap(st['overrides']);
    ovTdb = ov['dry_bulb'] != null;
    ovTnwb = ov['natural_wet_bulb'] != null;
    ovTg = ov['globe_temperature'] != null;
    final r = s.readings.isEmpty ? null : s.readings.last;
    tdb = jNum(ov['dry_bulb']) ?? r?.tdb ?? 32;
    tnwb = jNum(ov['natural_wet_bulb']) ?? r?.tnwb ?? 26;
    tg = jNum(ov['globe_temperature']) ?? r?.tg ?? 42;
    loadedFor = wsId;
    crewId = null;
  }

  Future<void> _do(Future<dynamic> Function(ApiClient api) f, String ok) async {
    final err = await context.read<AppState>().run(f);
    if (mounted) showResult(context, err, ok);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ws = s.selectedWorksite;
    if (ws == null) return const EmptyState(icon: Icons.location_off_outlined, title: 'No worksites');
    _syncFromStation(s, ws.id);
    final siteCrews = s.crews.where((c) => c.worksiteId == ws.id).toList();
    if (crewId == null || !siteCrews.any((c) => c.id == crewId)) crewId = siteCrews.isEmpty ? null : siteCrews.first.id;
    final st = s.stationStatus(ws.id) ?? {};

    return PageBody(maxWidth: 1400, children: [
      _runBar(s, ws, st),
      TwoColumn(
        breakpoint: 1100,
        leftFlex: 5,
        rightFlex: 6,
        left: _controls(s, ws, st, siteCrews),
        right: _results(s, ws),
      ),
    ]);
  }

  // ------------------------------------------------------------------ run bar
  Widget _runBar(AppState s, Worksite ws, J st) {
    final state = '${s.simulation['state'] ?? 'unknown'}';
    final speed = jNum(s.simulation['speed']) ?? 1;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusDot(state == 'running' ? 'running' : (state == 'paused' ? 'paused' : 'offline'), label: humanize(state)),
          Text(siteTime(st['sim_clock'] as String?, date: st['sim_date'] as String?), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text('${ws.name} · ${humanize('${st['scenario_id'] ?? ''}')}', style: t.bodySmall),
          const SizedBox(width: 8),
          if (state == 'running')
            OutlinedButton.icon(onPressed: () => _do((a) => a.post('/simulation/pause'), 'Paused'), icon: const Icon(Icons.pause, size: 18), label: const Text('Pause'))
          else
            FilledButton.icon(
              onPressed: () => _do((a) => a.post(state == 'paused' ? '/simulation/resume' : '/simulation/start'), 'Running'),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(state == 'paused' ? 'Resume' : 'Start'),
            ),
          TextButton.icon(onPressed: () => _do((a) => a.post('/simulation/step'), 'Advanced one minute'), icon: const Icon(Icons.skip_next, size: 18), label: const Text('+1 min')),
          SegmentedButton<double>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 1, label: Text('1×')),
              ButtonSegment(value: 2, label: Text('2×')),
              ButtonSegment(value: 5, label: Text('5×')),
              ButtonSegment(value: 10, label: Text('10×')),
            ],
            selected: {[1.0, 2.0, 5.0, 10.0].contains(speed) ? speed : 1.0},
            onSelectionChanged: (v) => _do((a) => a.post('/simulation/speed', {'speed': v.first}), 'Speed ${v.first.toStringAsFixed(0)}×'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'stop') _stop();
              if (v == 'reset') _reset();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'stop', child: Text('Stop simulation')),
              PopupMenuItem(value: 'reset', child: Text('Reset simulation...', style: TextStyle(color: HG.high))),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _stop() async {
    final ok = await confirmDialog(context,
        title: 'Stop the simulation?', message: 'No new readings will arrive. After about 15 seconds every assessment becomes "unavailable".', confirm: 'Stop');
    if (ok) _do((a) => a.post('/simulation/stop'), 'Simulation stopped');
  }

  Future<void> _reset() async {
    bool clear = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Reset simulation?'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Stations restart at minute 0. Adjustments, overrides and simulated faults are cleared.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clear,
                onChanged: (v) => setD(() => clear = v ?? false),
                title: const Text('Also delete all readings, alerts and interventions', style: TextStyle(fontSize: 14)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: HG.high), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    loadedFor = null;
    await _do((a) => a.post('/simulation/reset', {'clear_history': clear}), clear ? 'Reset and history cleared' : 'Simulation reset');
  }

  // ------------------------------------------------------------------ controls
  Widget _controls(AppState s, Worksite ws, J st, List<Crew> crews) => Card(
        child: DefaultTabController(
          length: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TabBar(isScrollable: true, padding: EdgeInsets.symmetric(horizontal: 8), tabs: [
              Tab(text: 'Scenario'),
              Tab(text: 'Crew'),
              Tab(text: 'Conditions'),
              Tab(text: 'Failures'),
            ]),
            SizedBox(
              height: 560,
              child: TabBarView(children: [
                _pad(_scenario(s, ws, st)),
                _pad(_crew(s, crews)),
                _pad(_conditions(ws)),
                _pad(_failures(s, ws, st)),
              ]),
            ),
          ]),
        ),
      );

  Widget _pad(Widget w) => ListView(padding: const EdgeInsets.all(20), children: [w]);

  Widget _hint(String text) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(text, style: Theme.of(context).textTheme.bodySmall));

  Widget _scenario(AppState s, Worksite ws, J st) {
    final current = st['scenario_id'];
    final options = s.scenarios.where((sc) => (sc['indoor'] == true) == (ws.environment == 'indoor')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _hint('Scenarios for ${ws.name} (${ws.environment}). Switch worksite in the header.'),
      for (final sc in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: sc['id'] == current ? null : () => _do((a) => a.post('/simulation/scenario', {'worksite_id': ws.id, 'scenario_id': sc['id']}), '${sc['name']} selected'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: sc['id'] == current ? const Color(0xFFF5F8FF) : Colors.white,
                border: Border.all(color: sc['id'] == current ? HG.primary : HG.border, width: sc['id'] == current ? 1.5 : 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(sc['id'] == current ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: sc['id'] == current ? HG.primary : HG.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${sc['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text('${sc['description']}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _crew(AppState s, List<Crew> crews) {
    final crew = crews.where((c) => c.id == crewId).firstOrNull;
    if (crew == null) return const EmptyState(icon: Icons.groups_outlined, title: 'No crews at this worksite');
    Future<void> set(String field, String value) => _do((a) => a.put('/crews/${crew.id}', {field: value}), '${crew.name}: ${humanize(field)} set to ${humanize(value)}');
    final clothing = jMap(s.meta['clothing']);
    Widget dd(String label, String value, Map<String, String> items, String field) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String>(
            key: ValueKey('$field-${crew.id}-$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null || v == value ? null : set(field, v),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _hint('Changes are saved to the crew and reassessed immediately.'),
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DropdownButtonFormField<String>(
          key: ValueKey('crew-$crewId'),
          initialValue: crewId,
          decoration: const InputDecoration(labelText: 'Crew'),
          items: [for (final c in crews) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => crewId = v),
        ),
      ),
      dd('Workload', crew.workload, {for (final w in workloadIds) w: humanize(w)}, 'workload'),
      dd('Acclimatization', crew.acclimatization, {for (final w in acclIds) w: humanize(w)}, 'acclimatization'),
      dd('Clothing', crew.clothing, {for (final e in clothing.entries) e.key: '${jMap(e.value)['label']}', 'unknown': 'Unknown'}, 'clothing'),
      dd('Work / rest schedule', crew.regime, regimeLabels, 'work_rest_regime'),
    ]);
  }

  Widget _slider(String label, double value, double min, double max, String Function(double) fmt, ValueChanged<double>? on, {int? divisions}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 14))),
          Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: fmt(value), onChanged: on)),
          SizedBox(width: 72, child: Text(fmt(value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _conditions(Worksite ws) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Adjust the weather', style: t.titleSmall),
      _hint('All WBGT inputs are recalculated consistently from these.'),
      _slider('Air temperature', tdbOffset, -5, 10, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} °C', (v) => setState(() => tdbOffset = v), divisions: 30),
      _slider('Humidity', rhOffset, -30, 30, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)} %', (v) => setState(() => rhOffset = v), divisions: 60),
      if (ws.environment == 'outdoor')
        _slider('Sunshine', solarScale, 0, 1.5, (v) => '${(v * 100).toStringAsFixed(0)} %', (v) => setState(() => solarScale = v), divisions: 30),
      _slider('Wind', windOffset, -2, 3, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} m/s', (v) => setState(() => windOffset = v), divisions: 50),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
          onPressed: () {
            setState(() {
              tdbOffset = rhOffset = windOffset = 0;
              solarScale = 1;
            });
            _do((a) => a.post('/simulation/adjust', {'worksite_id': ws.id}), 'Back to scenario baseline');
          },
          child: const Text('Reset'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _do(
              (a) => a.post('/simulation/adjust', {'worksite_id': ws.id, 'tdb_offset': tdbOffset, 'rh_offset': rhOffset, 'solar_scale': solarScale, 'wind_offset': windOffset}),
              'Applied - visible from the next reading'),
          child: const Text('Apply'),
        ),
      ]),
      const SizedBox(height: 16),
      const Divider(),
      Details(title: 'Advanced: set sensor values directly', children: [
        _hint('Overrides are flagged on every reading. Implausible values (e.g. wet-bulb above air temperature) are rejected.'),
        Row(children: [
          Checkbox(value: ovTdb, onChanged: (v) => setState(() => ovTdb = v ?? false)),
          Expanded(child: _slider('Air', tdb, 15, 50, (v) => '${v.toStringAsFixed(1)} °C', ovTdb ? (v) => setState(() => tdb = v) : null, divisions: 70)),
        ]),
        Row(children: [
          Checkbox(value: ovTnwb, onChanged: (v) => setState(() => ovTnwb = v ?? false)),
          Expanded(child: _slider('Wet-bulb', tnwb, 10, 40, (v) => '${v.toStringAsFixed(1)} °C', ovTnwb ? (v) => setState(() => tnwb = v) : null, divisions: 60)),
        ]),
        Row(children: [
          Checkbox(value: ovTg, onChanged: (v) => setState(() => ovTg = v ?? false)),
          Expanded(child: _slider('Globe', tg, 15, 70, (v) => '${v.toStringAsFixed(1)} °C', ovTg ? (v) => setState(() => tg = v) : null, divisions: 110)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () {
              setState(() => ovTdb = ovTnwb = ovTg = false);
              _do((a) => a.post('/simulation/override', {'worksite_id': ws.id, 'clear': true}), 'Overrides cleared');
            },
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: !(ovTdb || ovTnwb || ovTg)
                ? null
                : () async {
                    await context.read<AppState>().api.post('/simulation/override', {'worksite_id': ws.id, 'clear': true});
                    await _do(
                        (a) => a.post('/simulation/override', {
                              'worksite_id': ws.id,
                              if (ovTdb) 'dry_bulb': double.parse(tdb.toStringAsFixed(1)),
                              if (ovTnwb) 'natural_wet_bulb': double.parse(tnwb.toStringAsFixed(1)),
                              if (ovTg) 'globe_temperature': double.parse(tg.toStringAsFixed(1)),
                            }),
                        'Override applied');
                  },
            child: const Text('Apply override'),
          ),
        ]),
      ]),
    ]);
  }

  Widget _failures(AppState s, Worksite ws, J st) {
    final t = Theme.of(context).textTheme;
    final faults = jMap(st['manual_faults']);
    final netDown = st['manual_network_down'] == true;
    final dbOutage = s.simulation['db_outage'] == true;
    Widget block(String title, String desc, Widget controls, {bool active = false}) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: active ? HG.high.withValues(alpha: 0.4) : HG.border),
            color: active ? const Color(0xFFFEF2F2) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: t.titleSmall),
            const SizedBox(height: 2),
            Text(desc, style: t.bodySmall),
            const SizedBox(height: 12),
            controls,
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _hint('HeatGuard must flag missing or stale data. It never shows it as safe.'),
      block(
        'Sensor failure',
        faults.isEmpty ? 'Make a probe stop reporting or send invalid values.' : 'Active: ${faults.entries.map((e) => '${humanize(e.key)} (${e.value})').join(', ')}',
        active: faults.isNotEmpty,
        faults.isNotEmpty
            ? Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: () => _do((a) => a.post('/simulation/sensor-restore', {'worksite_id': ws.id}), 'Sensors restored'), child: const Text('Restore sensors')),
              )
            : Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: faultSensor,
                    decoration: const InputDecoration(labelText: 'Sensor'),
                    items: const [
                      DropdownMenuItem(value: 'globe', child: Text('Globe')),
                      DropdownMenuItem(value: 'wet_bulb', child: Text('Wet-bulb')),
                      DropdownMenuItem(value: 'dry_bulb', child: Text('Air')),
                      DropdownMenuItem(value: 'all', child: Text('Whole station')),
                    ],
                    onChanged: (v) => setState(() => faultSensor = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: faultMode,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'missing', child: Text('No signal')),
                      DropdownMenuItem(value: 'invalid', child: Text('Bad values')),
                    ],
                    onChanged: (v) => setState(() => faultMode = v!),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _do((a) => a.post('/simulation/sensor-failure', {'worksite_id': ws.id, 'sensor': faultSensor, 'mode': faultMode}), 'Sensor failure triggered'),
                  child: const Text('Trigger'),
                ),
              ]),
      ),
      block(
        'Network outage',
        netDown ? '${st['buffered_readings'] ?? 0} readings are queued at the station.' : 'Disconnect the station. Readings queue up and sync when restored.',
        active: netDown,
        Align(
          alignment: Alignment.centerLeft,
          child: netDown
              ? FilledButton(onPressed: () => _do((a) => a.post('/simulation/network-restore', {'worksite_id': ws.id}), 'Connection restored'), child: const Text('Restore connection'))
              : OutlinedButton(onPressed: () => _do((a) => a.post('/simulation/network-failure', {'worksite_id': ws.id}), 'Network outage started'), child: const Text('Disconnect station')),
        ),
      ),
      block(
        'Station battery',
        st['battery_fault'] == true
            ? 'Battery failing: ${fmtNum(st['battery_pct'], digits: 0)}% left. A warning appears below 25%; at 0% the station stops.'
            : 'Battery ${fmtNum(st['battery_pct'], digits: 0)}% (solar charged). Simulate a failing battery or panel.',
        active: st['battery_fault'] == true,
        Align(
          alignment: Alignment.centerLeft,
          child: st['battery_fault'] == true
              ? FilledButton(onPressed: () => _do((a) => a.post('/simulation/battery-fault', {'worksite_id': ws.id, 'enabled': false}), 'Battery replaced'), child: const Text('Replace battery'))
              : OutlinedButton(onPressed: () => _do((a) => a.post('/simulation/battery-fault', {'worksite_id': ws.id, 'enabled': true}), 'Battery failing'), child: const Text('Fail battery')),
        ),
      ),
      block(
        'Dust (shamal)',
        (jNum(st['dust_index']) ?? 0) > 0.05
            ? 'Dust fouling ${(100 * (jNum(st['dust_index']) ?? 0)).toStringAsFixed(0)}%. Heavy fouling makes readings unreliable, so assessments become unavailable.'
            : 'Dust coats the globe and dries the wick. HeatGuard must detect it and ask for cleaning.',
        active: (jNum(st['dust_index']) ?? 0) > 0.05,
        Align(
          alignment: Alignment.centerLeft,
          child: (jNum(st['dust_index']) ?? 0) > 0.05
              ? FilledButton(onPressed: () => _do((a) => a.post('/simulation/dust', {'worksite_id': ws.id, 'enabled': false}), 'Station cleaned'), child: const Text('Clean station'))
              : OutlinedButton(onPressed: () => _do((a) => a.post('/simulation/dust', {'worksite_id': ws.id, 'enabled': true}), 'Dust event started'), child: const Text('Start dust event')),
        ),
      ),
      block(
        'Worker strain (consented wearable)',
        'Make one consenting worker in ${s.crewById(crewId ?? '')?.name ?? 'the selected crew'} show sustained high heart rate (choose the crew in the Crew tab).',
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => _strain(1.0), child: const Text('Simulate strain')),
          TextButton(onPressed: () => _strain(0.0), child: const Text('Recover')),
        ]),
      ),
      block(
        'Database outage',
        'Writes are queued, not lost. Pending: ${s.health['pending_sync_writes'] ?? 0}',
        active: dbOutage,
        Align(
          alignment: Alignment.centerLeft,
          child: dbOutage
              ? FilledButton(onPressed: () => _do((a) => a.post('/simulation/database-outage', {'enabled': false}), 'Database restored'), child: const Text('Restore database'))
              : OutlinedButton(onPressed: () => _do((a) => a.post('/simulation/database-outage', {'enabled': true}), 'Database outage started'), child: const Text('Simulate outage')),
        ),
      ),
    ]);
  }

  Future<void> _strain(double level) async {
    final s = context.read<AppState>();
    if (crewId == null) return;
    try {
      final badges = jList(await s.api.get('/worker/badges/$crewId')).where((b) => b['sharing'] == true).toList();
      if (badges.isEmpty) {
        if (mounted) showResult(context, 'No consenting wearable users in this crew', '');
        return;
      }
      final targets = level > 0 ? [badges.first] : badges;
      for (final b in targets) {
        await s.api.post('/simulation/worker-strain', {'worker_id': b['worker_id'], 'level': level});
      }
      if (mounted) showResult(context, null, level > 0 ? 'Badge ${badges.first['badge']}: strain simulated' : 'Workers recovered');
    } catch (e) {
      if (mounted) showResult(context, '$e', '');
    }
  }

  // ------------------------------------------------------------------ results
  Widget _results(AppState s, Worksite ws) {
    final t = Theme.of(context).textTheme;
    final a = crewId == null ? null : s.assessmentFor(crewId!);
    final r = s.readings.isEmpty ? null : s.readings.last;
    final crewAlerts = s.alerts.where((x) => !x.resolved && (x.crewId == crewId || (x.crewId == '__site__' && x.worksiteId == ws.id))).toList();
    String n(double? v) => v == null ? '?' : v.toStringAsFixed(1);
    final calc = r == null
        ? 'No reading yet'
        : r.wbgt == null
            ? 'WBGT cannot be calculated: ${r.issues.map((i) => '${humanize(i['field'])} ${i['issue']}').join(', ')}'
            : (r.formula ?? '').contains('0.1*Tdb')
                ? 'WBGT = 0.7 × ${n(r.tnwb)} + 0.2 × ${n(r.tg)} + 0.1 × ${n(r.tdb)} = ${n(r.wbgt)} °C'
                : 'WBGT = 0.7 × ${n(r.tnwb)} + 0.3 × ${n(r.tg)} = ${n(r.wbgt)} °C';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionCard(
        title: 'Result for ${s.crewById(crewId ?? '')?.name ?? '-'}',
        subtitle: 'Updates with every simulated reading',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: HG.subtle, borderRadius: BorderRadius.circular(8)),
            child: Text(calc, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: r?.wbgt == null ? const Color(0xFF5B21B6) : HG.text)),
          ),
          const SizedBox(height: 20),
          if (a == null) const EmptyState(icon: Icons.hourglass_empty, title: 'Waiting for an assessment') else AssessmentPanel(a, compact: true),
          if (crewAlerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            Text('Open alerts', style: t.titleSmall),
            const SizedBox(height: 8),
            for (final al in crewAlerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SevChip(al.severity, short: true, label: al.type == 'data_quality' ? 'Data unavailable' : null),
                  const SizedBox(width: 10),
                  Expanded(child: Text(al.acknowledged ? 'Acknowledged' : 'Not acknowledged', style: t.bodySmall)),
                  if (!al.acknowledged)
                    TextButton(onPressed: () => _do((api) => api.post('/alerts/${al.id}/acknowledge', {'supervisor_id': 'supervisor-demo'}), 'Alert acknowledged'), child: const Text('Acknowledge')),
                  if (al.type == 'heat_risk') TextButton(onPressed: () => showInterventionForm(context, alert: al), child: const Text('Record action')),
                ]),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 24),
      SectionCard(
        title: 'Last hour',
        child: WbgtChart(readings: s.readings.length > 60 ? s.readings.sublist(s.readings.length - 60) : s.readings, height: 180),
      ),
    ]);
  }
}
