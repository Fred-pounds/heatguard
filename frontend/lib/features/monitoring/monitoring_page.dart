import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/assessment_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/wbgt_chart.dart';

class MonitoringPage extends StatefulWidget {
  const MonitoringPage({super.key});
  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  bool showComponents = true;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ws = s.selectedWorksite;
    if (ws == null) return const EmptyState(icon: Icons.location_off, title: 'No worksites');
    final crews = s.crews.where((c) => c.worksiteId == ws.id && (s.zoneFilter == null || c.zone == s.zoneFilter)).toList();
    final shown = s.crewFilter == null ? crews : crews.where((c) => c.id == s.crewFilter).toList();
    final reading = s.readings.isEmpty ? null : s.readings.last;
    final focus = shown.length == 1 ? s.assessmentFor(shown.first.id) : null;
    final limits = <String, double>{};
    if (focus?.limit != null) {
      limits['${focus!.limit!['limit_type']} (${focus.crewName})'] = jNum(focus.limit!['limit_at_current_regime'])! - jNum(focus.limit!['clothing_adjustment'])!;
    }

    return PageBody(children: [
      _Filters(ws: ws, crews: crews),
      _CurrentReading(ws: ws, reading: reading),
      SectionCard(
        title: 'Environmental trend',
        subtitle: limits.isEmpty
            ? 'Select a single crew to overlay its applicable limit (adjusted for clothing)'
            : 'Dashed line: applicable limit expressed as measured WBGT (limit minus clothing adjustment)',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Components', style: TextStyle(fontSize: 12)),
          Switch(value: showComponents, onChanged: (v) => setState(() => showComponents = v)),
        ]),
        child: WbgtChart(readings: s.readings, showComponents: showComponents, limits: limits, height: 280),
      ),
      Text('Crew assessments (${shown.length})', style: Theme.of(context).textTheme.titleMedium),
      if (shown.isEmpty) const SectionCard(child: EmptyState(icon: Icons.groups_outlined, title: 'No crews match the filters')),
      for (final c in shown) _CrewAssessment(crew: c, a: s.assessmentFor(c.id), expanded: shown.length == 1),
    ]);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.ws, required this.crews});
  final Worksite ws;
  final List<Crew> crews;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget dd<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> on) => SizedBox(
          key: ValueKey('$label-$value'),
          width: 230,
          child: DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: items,
            onChanged: on,
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          dd<String>('Worksite', ws.id, [for (final w in s.worksites) DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))],
              (v) => s.selectWorksite(v)),
          dd<String?>('Work zone', s.zoneFilter, [
            const DropdownMenuItem(value: null, child: Text('All zones')),
            for (final z in ws.zones) DropdownMenuItem(value: z, child: Text(z)),
          ], (v) => v == null ? s.setFilters(clearZone: true, clearCrew: true) : s.setFilters(zone: v, clearCrew: true)),
          dd<String?>('Crew', s.crewFilter, [
            const DropdownMenuItem(value: null, child: Text('All crews')),
            for (final c in crews) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ], (v) => v == null ? s.setFilters(clearCrew: true) : s.setFilters(crew: v)),
          dd<int>('Time range', s.timeRangeMinutes, const [
            DropdownMenuItem(value: 30, child: Text('Last 30 sim. min')),
            DropdownMenuItem(value: 60, child: Text('Last 60 sim. min')),
            DropdownMenuItem(value: 120, child: Text('Last 2 sim. hours')),
            DropdownMenuItem(value: 240, child: Text('Last 4 sim. hours')),
          ], (v) => s.setTimeRange(v ?? 120)),
        ]),
      ),
    );
  }
}

class _CurrentReading extends StatelessWidget {
  const _CurrentReading({required this.ws, required this.reading});
  final Worksite ws;
  final Reading? reading;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = reading;
    final status = ws.sensorStatus;
    final st = s.stationStatus(ws.id);
    Widget tile(String label, double? v, String unit, {String? field, bool big = false}) {
      final bad = r != null && field != null && r.issues.any((i) => i['field'] == field);
      final overridden = r != null && field != null && r.overrides.contains(field);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bad ? HG.unavailable.withValues(alpha: 0.07) : (big ? HG.primary.withValues(alpha: 0.05) : HG.bg),
          border: Border.all(color: bad ? HG.unavailable.withValues(alpha: 0.5) : HG.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(bad ? 'INVALID / MISSING' : '${fmtNum(v, digits: big ? 1 : 1)}$unit',
              style: TextStyle(fontSize: bad ? 13 : (big ? 26 : 20), fontWeight: FontWeight.w800, color: bad ? HG.unavailable : HG.text)),
          if (overridden) const Pill('MANUAL OVERRIDE', color: HG.accent),
          if (bad) Text(r.issues.firstWhere((i) => i['field'] == field)['detail'], style: const TextStyle(fontSize: 10.5, color: HG.muted), maxLines: 2),
        ]),
      );
    }

    return SectionCard(
      title: 'Current environmental readings',
      subtitle: '${ws.name} · ${ws.location} · ${humanize(ws.environment)} · station ${ws.j['station_id']}',
      trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusDot(status, label: 'Sensor: $status'),
        const SimulatedBadge(),
      ]),
      child: r == null
          ? const EmptyState(icon: Icons.sensors_off, title: 'No readings received')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (status == 'stale' || status == 'offline')
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: HG.unavailable.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'No fresh data for ${fmtDuration(ws.status['reading_age_seconds'] as num?)}. Values below are the LAST VALID reading, not live conditions.'
                    '${st != null && st['network_up'] == false ? ' Station uplink down: ${st['buffered_readings']} readings queued at the edge (unsynchronised).' : ''}',
                    style: const TextStyle(color: HG.unavailable, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              ResponsiveGrid(minItemWidth: 150, spacing: 10, children: [
                tile('WBGT', r.wbgt, ' °C', big: true),
                tile('Dry-bulb', r.tdb, ' °C', field: 'dry_bulb'),
                tile('Nat. wet-bulb', r.tnwb, ' °C', field: 'natural_wet_bulb'),
                tile('Globe', r.tg, ' °C', field: 'globe_temperature'),
                tile('Rel. humidity', r.rh, ' %', field: 'relative_humidity'),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Text('Formula: ${r.formula ?? 'not computable (missing components)'}', style: const TextStyle(fontSize: 12, fontFamily: 'Roboto', fontFeatures: [FontFeature.tabularFigures()])),
                Text('Direct sun: ${r.directSolar == null ? 'unknown' : (r.directSolar! ? 'yes' : 'no')}', style: const TextStyle(fontSize: 12)),
                Text('Simulated clock: ${r.simClock ?? '-'}', style: const TextStyle(fontSize: 12)),
                Text('Received: ${fmtTime(r.receivedAt)} (${ago(r.receivedAt)})', style: const TextStyle(fontSize: 12)),
                Text('60-min mean WBGT: ${fmtNum(ws.rollingMean)} °C', style: const TextStyle(fontSize: 12)),
                if (r.lateSync) const Pill('LATE SYNC (queued during outage)', color: HG.unavailable),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 12, children: [
                for (final e in r.sensorStatus.entries) StatusDot(e.value == 'ok' ? 'ok' : 'fault', label: '${humanize(e.key)}: ${e.value}'),
              ]),
            ]),
    );
  }
}

class _CrewAssessment extends StatelessWidget {
  const _CrewAssessment({required this.crew, required this.a, required this.expanded});
  final Crew crew;
  final Assessment? a;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final sev = Sev.of(a?.category);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: sev.color, width: 4))),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('crew-${crew.id}-$expanded'),
            initiallyExpanded: expanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(crew.name, style: Theme.of(context).textTheme.titleMedium),
              SevChip(a?.category),
              if (a?.effectiveWbgt != null) Text('eff. WBGT ${fmtNum(a!.effectiveWbgt)} °C', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (a?.limit != null) Text('${a!.limit!['limit_type']} ${fmtNum(a!.limit!['limit_at_current_regime'])} °C', style: const TextStyle(fontSize: 12.5, color: HG.muted)),
            ]),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 12, children: [
                Text('${crew.zone} · ${crew.workerCount} workers', style: const TextStyle(fontSize: 12)),
                Text('Workload: ${humanize(crew.workload)}', style: const TextStyle(fontSize: 12)),
                Text('Acclimatization: ${humanize(crew.acclimatization)}',
                    style: TextStyle(fontSize: 12, color: crew.acclimatization == 'acclimatized' ? HG.text : HG.elevated, fontWeight: FontWeight.w600)),
                Text('Regime: ${regimeLabels[crew.regime]}', style: const TextStyle(fontSize: 12)),
                Text('Completeness: ${pct(a?.completeness)}', style: const TextStyle(fontSize: 12)),
                Text('Updated ${ago(a?.timestamp)}', style: const TextStyle(fontSize: 12, color: HG.muted)),
              ]),
            ),
            children: [if (a == null) const EmptyState(icon: Icons.hourglass_empty, title: 'Awaiting first assessment') else AssessmentPanel(a!)],
          ),
        ),
      ),
    );
  }
}
