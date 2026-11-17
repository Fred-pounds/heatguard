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
  // driver adjustments
  double tdbOffset = 0, rhOffset = 0, solarScale = 1, windOffset = 0;
  // direct overrides
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
    final err = await context.read<AppState>().run((api) => f(api));
    if (mounted) showResult(context, err, ok);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ws = s.selectedWorksite;
    if (ws == null) return const EmptyState(icon: Icons.location_off, title: 'No worksites');
    _syncFromStation(s, ws.id);
    final siteCrews = s.crews.where((c) => c.worksiteId == ws.id).toList();
    crewId ??= siteCrews.isEmpty ? null : siteCrews.first.id;
    if (crewId != null && !siteCrews.any((c) => c.id == crewId)) crewId = siteCrews.isEmpty ? null : siteCrews.first.id;
    final st = s.stationStatus(ws.id) ?? {};
    final wide = MediaQuery.sizeOf(context).width >= 1280;

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _runControls(s),
      const SizedBox(height: 16),
      _scenario(s, ws, st),
      const SizedBox(height: 16),
      _workContext(s, siteCrews),
      const SizedBox(height: 16),
      _environment(s, ws),
      const SizedBox(height: 16),
      _overrides(s, ws),
      const SizedBox(height: 16),
      _failures(s, ws, st),
    ]);
    final results = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stationStatus(s, ws, st),
      const SizedBox(height: 16),
      _calculation(s),
      const SizedBox(height: 16),
      _assessment(s),
      const SizedBox(height: 16),
      _alertsAndInterventions(s, ws),
    ]);

    if (!wide) return PageBody(children: [controls, results]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 440, child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 8, 40), children: [controls])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(8, 16, 24, 40), children: [results])),
    ]);
  }

  // ------------------------------------------------------------------ controls
  Widget _runControls(AppState s) {
    final state = '${s.simulation['state'] ?? 'unknown'}';
    final speed = jNum(s.simulation['speed']) ?? 1;
    return SectionCard(
      title: 'Simulation run',
      subtitle: '1 tick = 1 simulated minute · every ${s.simulation['tick_interval_seconds'] ?? '-'} s',
      trailing: StatusDot(state == 'running' ? 'running' : (state == 'paused' ? 'paused' : 'offline'), label: humanize(state)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (state == 'stopped')
            FilledButton.icon(onPressed: () => _do((a) => a.post('/simulation/start'), 'Simulation started'), icon: const Icon(Icons.play_arrow), label: const Text('Start')),
          if (state == 'running')
            FilledButton.tonalIcon(onPressed: () => _do((a) => a.post('/simulation/pause'), 'Simulation paused'), icon: const Icon(Icons.pause), label: const Text('Pause')),
          if (state == 'paused')
            FilledButton.icon(onPressed: () => _do((a) => a.post('/simulation/resume'), 'Simulation resumed'), icon: const Icon(Icons.play_arrow), label: const Text('Resume')),
          if (state != 'stopped')
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Stop simulation?', message: 'No new readings will arrive. After a short delay all assessments will become "unavailable" (stale data).', confirm: 'Stop');
                if (ok) _do((a) => a.post('/simulation/stop'), 'Simulation stopped');
              },
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          OutlinedButton.icon(onPressed: () => _do((a) => a.post('/simulation/step'), 'Advanced 1 simulated minute'), icon: const Icon(Icons.skip_next), label: const Text('Step +1 min')),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: HG.high),
            onPressed: () => _reset(),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('Speed', style: TextStyle(fontSize: 12, color: HG.muted)),
        const SizedBox(height: 4),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0.5, label: Text('0.5×')),
            ButtonSegment(value: 1, label: Text('1×')),
            ButtonSegment(value: 2, label: Text('2×')),
            ButtonSegment(value: 5, label: Text('5×')),
            ButtonSegment(value: 10, label: Text('10×')),
          ],
          selected: {speed},
          onSelectionChanged: (v) => _do((a) => a.post('/simulation/speed', {'speed': v.first}), 'Speed set to ${v.first}×'),
        ),
      ]),
    );
  }

  Future<void> _reset() async {
    bool clear = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Reset simulation?'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('All virtual stations restart at minute 0. Adjustments, overrides and simulated faults are cleared.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clear,
                onChanged: (v) => setD(() => clear = v ?? false),
                title: const Text('Also permanently delete readings, assessments, alerts, interventions and events', style: TextStyle(fontSize: 13, color: HG.high)),
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
    await _do((a) => a.post('/simulation/reset', {'clear_history': clear}), clear ? 'Simulation reset and history cleared' : 'Simulation reset');
  }

  Widget _scenario(AppState s, Worksite ws, J st) {
    final current = st['scenario_id'];
    final options = s.scenarios.where((sc) => (sc['indoor'] == true) == (ws.environment == 'indoor')).toList();
    return SectionCard(
      title: 'Scenario · ${ws.name}',
      subtitle: '${humanize(ws.environment)} worksite - scenarios matching this environment. Change worksite in the header.',
      child: Column(children: [
        for (final sc in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: sc['id'] == current ? HG.primary.withValues(alpha: 0.07) : HG.bg,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: sc['id'] == current
                    ? null
                    : () => _do((a) => a.post('/simulation/scenario', {'worksite_id': ws.id, 'scenario_id': sc['id']}), 'Scenario ${sc['code']} selected'),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: sc['id'] == current ? HG.primary : HG.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: sc['id'] == current ? HG.primary : HG.border,
                      child: Text('${sc['code']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sc['id'] == current ? Colors.white : HG.text)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${sc['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('${sc['description']}', style: const TextStyle(fontSize: 11.5, color: HG.muted)),
                      ]),
                    ),
                    if (sc['id'] == current) const Icon(Icons.check_circle, color: HG.primary, size: 18),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _workContext(AppState s, List<Crew> crews) {
    Crew? crew;
    for (final c in crews) {
      if (c.id == crewId) crew = c;
    }
    Future<void> set(String field, String value) =>
        _do((a) => a.put('/crews/${crew!.id}', {field: value}), '${crew!.name}: ${humanize(field)} → ${humanize(value)} (reassessed)');
    final clothing = jMap(s.meta['clothing']);
    return SectionCard(
      title: 'Work context',
      subtitle: 'Changes are saved to the crew and reassessed immediately.',
      child: crew == null
          ? const EmptyState(icon: Icons.groups_outlined, title: 'No crews at this worksite')
          : Column(children: [
              DropdownButtonFormField<String>(
                key: ValueKey('crew-$crewId'),
                initialValue: crewId,
                decoration: const InputDecoration(labelText: 'Crew'),
                items: [for (final c in crews) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => crewId = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('wl-${crew.id}-${crew.workload}'),
                initialValue: crew.workload,
                decoration: const InputDecoration(labelText: 'Workload'),
                items: [for (final w in workloadIds) DropdownMenuItem(value: w, child: Text(humanize(w)))],
                onChanged: (v) => v == null || v == crew!.workload ? null : set('workload', v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('ac-${crew.id}-${crew.acclimatization}'),
                initialValue: crew.acclimatization,
                decoration: const InputDecoration(labelText: 'Acclimatization'),
                items: [for (final w in acclIds) DropdownMenuItem(value: w, child: Text(humanize(w)))],
                onChanged: (v) => v == null || v == crew!.acclimatization ? null : set('acclimatization', v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('cl-${crew.id}-${crew.clothing}'),
                initialValue: crew.clothing,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Clothing category'),
                items: [
                  for (final e in clothing.entries) DropdownMenuItem(value: e.key, child: Text('${jMap(e.value)['label']}', overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                ],
                onChanged: (v) => v == null || v == crew!.clothing ? null : set('clothing', v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('rg-${crew.id}-${crew.regime}'),
                initialValue: crew.regime,
                decoration: const InputDecoration(labelText: 'Work/rest regime'),
                items: [for (final e in regimeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => v == null || v == crew!.regime ? null : set('work_rest_regime', v),
              ),
            ]),
    );
  }

  Widget _slider(String label, double value, double min, double max, String Function(double) fmt, ValueChanged<double> on, {int? divisions}) =>
      Row(children: [
        SizedBox(width: 118, child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: fmt(value), onChanged: on)),
        SizedBox(width: 58, child: Text(fmt(value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]);

  Widget _environment(AppState s, Worksite ws) => SectionCard(
        title: 'Environmental conditions',
        subtitle: 'Adjusts the scenario drivers; all WBGT components are re-derived consistently.',
        child: Column(children: [
          _slider('Air temperature', tdbOffset, -5, 10, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} °C', (v) => setState(() => tdbOffset = v), divisions: 30),
          _slider('Humidity', rhOffset, -30, 30, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(0)} %', (v) => setState(() => rhOffset = v), divisions: 60),
          if (ws.environment == 'outdoor')
            _slider('Solar load', solarScale, 0, 1.5, (v) => '${(v * 100).toStringAsFixed(0)} %', (v) => setState(() => solarScale = v), divisions: 30),
          _slider('Air movement', windOffset, -2, 3, (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} m/s', (v) => setState(() => windOffset = v), divisions: 50),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () {
                setState(() {
                  tdbOffset = rhOffset = windOffset = 0;
                  solarScale = 1;
                });
                _do((a) => a.post('/simulation/adjust', {'worksite_id': ws.id}), 'Conditions reset to scenario baseline');
              },
              child: const Text('Baseline'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _do(
                  (a) => a.post('/simulation/adjust', {
                        'worksite_id': ws.id,
                        'tdb_offset': tdbOffset,
                        'rh_offset': rhOffset,
                        'solar_scale': solarScale,
                        'wind_offset': windOffset,
                      }),
                  'Conditions applied - visible from the next reading'),
              child: const Text('Apply'),
            ),
          ]),
        ]),
      );

  Widget _overrides(AppState s, Worksite ws) => SectionCard(
        title: 'Manual component overrides',
        subtitle: 'Directly set WBGT inputs. Implausible combinations are rejected; overridden values are flagged on every reading.',
        child: Column(children: [
          Row(children: [
            Checkbox(value: ovTdb, onChanged: (v) => setState(() => ovTdb = v ?? false)),
            Expanded(child: _slider('Dry-bulb', tdb, 15, 50, (v) => '${v.toStringAsFixed(1)} °C', ovTdb ? (v) => setState(() => tdb = v) : (_) {}, divisions: 70)),
          ]),
          Row(children: [
            Checkbox(value: ovTnwb, onChanged: (v) => setState(() => ovTnwb = v ?? false)),
            Expanded(child: _slider('Nat. wet-bulb', tnwb, 10, 40, (v) => '${v.toStringAsFixed(1)} °C', ovTnwb ? (v) => setState(() => tnwb = v) : (_) {}, divisions: 60)),
          ]),
          Row(children: [
            Checkbox(value: ovTg, onChanged: (v) => setState(() => ovTg = v ?? false)),
            Expanded(child: _slider('Globe', tg, 15, 70, (v) => '${v.toStringAsFixed(1)} °C', ovTg ? (v) => setState(() => tg = v) : (_) {}, divisions: 110)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () {
                setState(() => ovTdb = ovTnwb = ovTg = false);
                _do((a) => a.post('/simulation/override', {'worksite_id': ws.id, 'clear': true}), 'Overrides cleared');
              },
              child: const Text('Clear overrides'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: !(ovTdb || ovTnwb || ovTg)
                  ? null
                  : () async {
                      // replace any existing overrides with exactly the checked ones
                      await context.read<AppState>().api.post('/simulation/override', {'worksite_id': ws.id, 'clear': true});
                      await _do(
                          (a) => a.post('/simulation/override', {
                                'worksite_id': ws.id,
                                if (ovTdb) 'dry_bulb': double.parse(tdb.toStringAsFixed(1)),
                                if (ovTnwb) 'natural_wet_bulb': double.parse(tnwb.toStringAsFixed(1)),
                                if (ovTg) 'globe_temperature': double.parse(tg.toStringAsFixed(1)),
                              }),
                          'Override applied - visible from the next reading');
                    },
              child: const Text('Apply override'),
            ),
          ]),
        ]),
      );

  Widget _failures(AppState s, Worksite ws, J st) {
    final faults = jMap(st['manual_faults']);
    final netDown = st['manual_network_down'] == true;
    final dbOutage = s.simulation['db_outage'] == true;
    return SectionCard(
      title: 'Failure injection',
      subtitle: 'HeatGuard must flag missing or stale data - never show it as safe.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Sensor failure', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: faultSensor,
              decoration: const InputDecoration(labelText: 'Sensor'),
              items: const [
                DropdownMenuItem(value: 'globe', child: Text('Globe')),
                DropdownMenuItem(value: 'wet_bulb', child: Text('Nat. wet-bulb')),
                DropdownMenuItem(value: 'dry_bulb', child: Text('Dry-bulb')),
                DropdownMenuItem(value: 'humidity', child: Text('Humidity')),
                DropdownMenuItem(value: 'all', child: Text('Whole station')),
              ],
              onChanged: (v) => setState(() => faultSensor = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: faultMode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(value: 'missing', child: Text('No signal')),
                DropdownMenuItem(value: 'invalid', child: Text('Invalid value')),
              ],
              onChanged: (v) => setState(() => faultMode = v!),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: HG.high),
            onPressed: () => _do((a) => a.post('/simulation/sensor-failure', {'worksite_id': ws.id, 'sensor': faultSensor, 'mode': faultMode}),
                'Sensor failure triggered'),
            icon: const Icon(Icons.sensors_off, size: 18),
            label: const Text('Trigger failure'),
          ),
          OutlinedButton.icon(
            onPressed: faults.isEmpty ? null : () => _do((a) => a.post('/simulation/sensor-restore', {'worksite_id': ws.id}), 'Sensors restored'),
            icon: const Icon(Icons.sensors, size: 18),
            label: const Text('Restore sensors'),
          ),
        ]),
        if (faults.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Active: ${faults.entries.map((e) => '${e.key} (${e.value})').join(', ')}', style: const TextStyle(color: HG.high, fontSize: 12))),
        const Divider(height: 28),
        const Text('Network connectivity (station uplink)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!netDown)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: HG.high),
              onPressed: () => _do((a) => a.post('/simulation/network-failure', {'worksite_id': ws.id}), 'Network failure triggered'),
              icon: const Icon(Icons.wifi_off, size: 18),
              label: const Text('Trigger network failure'),
            )
          else
            FilledButton.icon(
              onPressed: () => _do((a) => a.post('/simulation/network-restore', {'worksite_id': ws.id}), 'Connectivity restored - queued readings synchronising'),
              icon: const Icon(Icons.wifi, size: 18),
              label: Text('Restore (${st['buffered_readings'] ?? 0} queued)'),
            ),
        ]),
        const Divider(height: 28),
        const Text('Database connectivity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: dbOutage,
          title: const Text('Simulate database outage', style: TextStyle(fontSize: 13)),
          subtitle: Text('Writes are queued, not lost. Pending: ${s.health['pending_sync_writes'] ?? 0}', style: const TextStyle(fontSize: 12)),
          onChanged: (v) => _do((a) => a.post('/simulation/database-outage', {'enabled': v}), v ? 'Database outage simulated' : 'Database restored - syncing queue'),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ results
  Widget _stationStatus(AppState s, Worksite ws, J st) {
    final faults = jMap(st['faults']);
    final ov = jMap(st['overrides']);
    return SectionCard(
      title: 'Virtual station ${st['station_id'] ?? ''}',
      trailing: const SimulatedBadge(),
      child: Wrap(spacing: 22, runSpacing: 10, children: [
        _kv('Simulated clock', '${st['sim_clock'] ?? '-'} (min ${st['sim_minute'] ?? '-'})'),
        _kv('Scenario', humanize('${st['scenario_id'] ?? '-'}')),
        _kvW('Sensors', StatusDot(faults.isEmpty ? 'ok' : 'fault', label: faults.isEmpty ? 'All OK' : faults.entries.map((e) => '${e.key}: ${e.value}').join(', '))),
        _kvW('Uplink', StatusDot(st['network_up'] == false ? 'offline' : 'ok', label: st['network_up'] == false ? 'DOWN · ${st['buffered_readings']} queued at edge' : 'Connected')),
        _kvW('Backend sees', StatusDot(ws.sensorStatus, label: '${ws.sensorStatus} · ${fmtDuration(ws.status['reading_age_seconds'] as num?)} old')),
        if (ov.isNotEmpty) _kvW('Overrides', Pill(ov.entries.map((e) => '${humanize(e.key)} ${e.value}').join(', '), color: HG.accent)),
      ]),
    );
  }

  Widget _kv(String k, String v) => _kvW(k, Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)));
  Widget _kvW(String k, Widget v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(), style: const TextStyle(fontSize: 10.5, color: HG.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        v,
      ]);

  Widget _calculation(AppState s) {
    final r = s.readings.isEmpty ? null : s.readings.last;
    String n(double? v) => v == null ? '?' : v.toStringAsFixed(2);
    String calc() {
      if (r == null) return 'No reading';
      if (r.wbgt == null) return 'WBGT not computable: ${r.issues.map((i) => '${humanize(i['field'])} ${i['issue']}').join(', ')}';
      if ((r.formula ?? '').contains('0.1*Tdb')) {
        return 'WBGT = 0.7×${n(r.tnwb)} + 0.2×${n(r.tg)} + 0.1×${n(r.tdb)} = ${n(r.wbgt)} °C   (outdoor, direct sun)';
      }
      return 'WBGT = 0.7×${n(r.tnwb)} + 0.3×${n(r.tg)} = ${n(r.wbgt)} °C   (indoor / no direct sun)';
    }

    return SectionCard(
      title: 'Simulated readings & WBGT calculation',
      subtitle: r == null ? null : 'Reading ${r.id} · ${r.simClock} · received ${ago(r.receivedAt)}${r.lateSync ? ' · LATE SYNC' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: HG.navy, borderRadius: BorderRadius.circular(6)),
          child: Text(calc(), style: const TextStyle(fontFamily: 'Roboto', fontFeatures: [FontFeature.tabularFigures()], color: Colors.white, fontSize: 13)),
        ),
        const SizedBox(height: 10),
        if (r != null)
          Wrap(spacing: 18, runSpacing: 6, children: [
            Text('Tdb ${fmtNum(r.tdb)} °C', style: TextStyle(fontWeight: FontWeight.w600, color: r.overrides.contains('dry_bulb') ? HG.accent : HG.text)),
            Text('Tnwb ${fmtNum(r.tnwb)} °C', style: TextStyle(fontWeight: FontWeight.w600, color: r.overrides.contains('natural_wet_bulb') ? HG.accent : HG.text)),
            Text('Tg ${fmtNum(r.tg)} °C', style: TextStyle(fontWeight: FontWeight.w600, color: r.overrides.contains('globe_temperature') ? HG.accent : HG.text)),
            Text('RH ${fmtNum(r.rh, digits: 0)} %', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Validity: ${r.validity}', style: TextStyle(fontWeight: FontWeight.w700, color: r.validity == 'valid' ? HG.routine : HG.unavailable)),
            if (r.overrides.isNotEmpty) const Pill('MANUAL OVERRIDE', color: HG.accent),
          ]),
        const SizedBox(height: 12),
        WbgtChart(readings: s.readings.length > 60 ? s.readings.sublist(s.readings.length - 60) : s.readings, showComponents: true, height: 200),
      ]),
    );
  }

  Widget _assessment(AppState s) {
    final a = crewId == null ? null : s.assessmentFor(crewId!);
    return SectionCard(
      title: 'Resulting assessment${a == null ? '' : ' · ${a.crewName}'}',
      subtitle: 'Updated on every simulated reading',
      child: a == null ? const EmptyState(icon: Icons.hourglass_empty, title: 'No assessment yet') : AssessmentPanel(a),
    );
  }

  Widget _alertsAndInterventions(AppState s, Worksite ws) {
    final alerts = s.alerts.where((a) => a.worksiteId == ws.id).take(6).toList();
    final ivs = s.interventions.where((i) => i.crewId == crewId).take(5).toList();
    return SectionCard(
      title: 'Alerts generated at this worksite',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (alerts.isEmpty) const EmptyState(icon: Icons.notifications_none, title: 'No alerts yet'),
        for (final a in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SevChip(a.severity, label: a.type == 'data_quality' ? 'Data unavailable' : null),
              const SizedBox(width: 8),
              Expanded(child: Text('${a.crewName} · ${fmtTime(a.timestamp)} · ${humanize(a.resolution)}', style: const TextStyle(fontSize: 12.5))),
              if (!a.acknowledged && !a.resolved)
                TextButton(
                  onPressed: () => _do((api) => api.post('/alerts/${a.id}/acknowledge', {'supervisor_id': 'supervisor-demo'}), 'Alert acknowledged'),
                  child: const Text('Acknowledge'),
                )
              else
                const Pill('Acknowledged', color: HG.routine),
              if (!a.resolved && a.type == 'heat_risk')
                TextButton(onPressed: () => showInterventionForm(context, alert: a), child: const Text('Intervene')),
            ]),
          ),
        const Divider(height: 24),
        Text('Intervention history - selected crew', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (ivs.isEmpty) const Text('None recorded', style: TextStyle(fontSize: 12.5, color: HG.muted)),
        for (final i in ivs)
          Text('• ${fmtTime(i.start)} ${i.actionLabel} - ${i.status}${i.outcome == null ? '' : ' - ${i.outcome}'}', style: const TextStyle(fontSize: 12.5)),
      ]),
    );
  }
}
