import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/assessment_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/wbgt_chart.dart';

class MonitoringPage extends StatefulWidget {
  const MonitoringPage({super.key});
  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  bool showComponents = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ws = s.selectedWorksite;
    if (ws == null) return const EmptyState(icon: Icons.location_off_outlined, title: 'No worksites');
    final crews = s.crews.where((c) => c.worksiteId == ws.id && (s.zoneFilter == null || c.zone == s.zoneFilter)).toList();
    final reading = s.readings.isEmpty ? null : s.readings.last;
    final focus = s.crewFilter == null ? null : s.assessmentFor(s.crewFilter!);
    final limits = <String, double>{};
    if (focus?.limit != null) {
      limits['${focus!.crewName} limit'] =
          jNum(focus.limit!['limit_at_current_regime'])! - (jNum(focus.limit!['clothing_adjustment']) ?? 0);
    }

    return PageBody(children: [
      _Toolbar(ws: ws, crews: crews),
      _Conditions(ws: ws, reading: reading),
      SectionCard(
        title: 'Trend',
        subtitle: limits.isEmpty ? 'Select a crew above to compare with its limit' : 'Dashed line: ${limits.keys.first} (expressed as measured WBGT)',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Show components', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 4),
          Switch(value: showComponents, onChanged: (v) => setState(() => showComponents = v)),
        ]),
        child: WbgtChart(readings: s.readings, showComponents: showComponents, limits: limits, height: 260),
      ),
      SectionCard(
        title: 'Crews at ${ws.name}',
        subtitle: 'Select a crew to see its full assessment',
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: crews.isEmpty
            ? const EmptyState(icon: Icons.groups_outlined, title: 'No crews match the filters')
            : Column(children: [
                for (var i = 0; i < crews.length; i++) ...[
                  if (i > 0) const Divider(),
                  _CrewRow(crew: crews[i], a: s.assessmentFor(crews[i].id)),
                ],
              ]),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Details(title: 'System events', icon: Icons.history, children: [_Events(events: jList(s.overview['recent_events']))]),
        ),
      ),
    ]);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.ws, required this.crews});
  final Worksite ws;
  final List<Crew> crews;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String?>(
          key: ValueKey('zone-${ws.id}-${s.zoneFilter}'),
          initialValue: s.zoneFilter,
          decoration: const InputDecoration(labelText: 'Zone'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All zones')),
            for (final z in ws.zones) DropdownMenuItem(value: z, child: Text(z)),
          ],
          onChanged: (v) => v == null ? s.setFilters(clearZone: true, clearCrew: true) : s.setFilters(zone: v, clearCrew: true),
        ),
      ),
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<String?>(
          key: ValueKey('crew-${ws.id}-${s.crewFilter}'),
          initialValue: s.crewFilter,
          decoration: const InputDecoration(labelText: 'Compare with crew limit'),
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            for (final c in crews) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => v == null ? s.setFilters(clearCrew: true) : s.setFilters(crew: v),
        ),
      ),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 30, label: Text('30 min')),
          ButtonSegment(value: 60, label: Text('1 h')),
          ButtonSegment(value: 120, label: Text('2 h')),
          ButtonSegment(value: 240, label: Text('4 h')),
        ],
        selected: {s.timeRangeMinutes},
        onSelectionChanged: (v) => s.setTimeRange(v.first),
      ),
    ]);
  }
}

class _Conditions extends StatelessWidget {
  const _Conditions({required this.ws, required this.reading});
  final Worksite ws;
  final Reading? reading;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = reading;
    final status = ws.sensorStatus;
    final st = s.stationStatus(ws.id);
    final stale = status == 'stale' || status == 'offline';

    Widget metric(String label, double? v, String unit, {String? field, bool big = false}) {
      final bad = (r != null && field != null && r.issues.any((i) => i['field'] == field)) || (r != null && field == null && v == null);
      final over = r != null && field != null && r.overrides.contains(field);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(bad ? (field == null ? 'Cannot calculate' : 'No valid data') : '${fmtNum(v)}$unit',
            style: TextStyle(fontSize: bad ? 15 : (big ? 30 : 22), fontWeight: FontWeight.w700, color: bad ? HG.unavailable : HG.text, height: 1.15)),
        if (over) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Manual', color: HG.accent)),
      ]);
    }

    return SectionCard(
      title: 'Current conditions',
      subtitle: '${ws.name} · ${humanize(ws.environment)} · ${r?.simClock == null ? '' : '${siteTime(r!.simClock, date: r.simDate)} · '}updated ${ago(r?.receivedAt)}',
      trailing: StatusDot(status, label: switch (status) {
        'ok' => 'Sensors normal',
        'degraded' => 'Sensor problem',
        'fault' => 'Sensor fault',
        'stale' => 'No fresh data',
        _ => 'Offline',
      }),
      child: r == null
          ? const EmptyState(icon: Icons.sensors_off_outlined, title: 'No readings received yet')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (stale)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: HG.unavailable.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'No fresh data for ${fmtDuration(ws.status['reading_age_seconds'] as num?)}. The values below are the last valid reading, not live conditions.'
                    '${st != null && st['network_up'] == false ? ' ${st['buffered_readings']} readings are queued at the station.' : ''}',
                    style: const TextStyle(color: Color(0xFF5B21B6), fontWeight: FontWeight.w600),
                  ),
                ),
              ResponsiveGrid(minItemWidth: 150, spacing: 24, children: [
                metric('WBGT', r.wbgt, ' °C', big: true),
                metric('Air (dry-bulb)', r.tdb, ' °C', field: 'dry_bulb'),
                metric('Natural wet-bulb', r.tnwb, ' °C', field: 'natural_wet_bulb'),
                metric('Globe', r.tg, ' °C', field: 'globe_temperature'),
                metric('Humidity', r.rh, ' %', field: 'relative_humidity'),
              ]),
              const SizedBox(height: 16),
              Text(
                [
                  r.directSolar == true ? 'Direct sun' : (ws.environment == 'indoor' ? 'Indoor' : 'No direct sun'),
                  '60-min average ${fmtNum(ws.rollingMean)} °C',
                  if (r.lateSync) 'Delivered late after an outage',
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
    );
  }
}

class _CrewRow extends StatelessWidget {
  const _CrewRow({required this.crew, required this.a});
  final Crew crew;
  final Assessment? a;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showCrewAssessment(context, crew.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(crew.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${crew.zone} · ${humanize(crew.workload)} work · ${humanize(crew.acclimatization)}', style: t.bodySmall),
            ]),
          ),
          if (!narrow)
            Expanded(
              flex: 2,
              child: Text(
                a?.effectiveWbgt == null || a?.limit == null ? '-' : '${fmtNum(a!.effectiveWbgt)} °C  /  limit ${fmtNum(a!.limit!['limit_at_current_regime'])} °C',
                style: t.bodyMedium,
              ),
            ),
          SizedBox(width: 190, child: Align(alignment: Alignment.centerRight, child: SevChip(a?.category))),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: HG.muted),
        ]),
      ),
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.events});
  final List<J> events;
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return Text('No events yet.', style: Theme.of(context).textTheme.bodySmall);
    return Column(children: [
      for (final e in events)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 80, child: Text(fmtTime(e['timestamp']), style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text('${humanize(e['type'])} - ${e['detail']}', style: const TextStyle(fontSize: 13.5))),
          ]),
        ),
    ]);
  }
}
