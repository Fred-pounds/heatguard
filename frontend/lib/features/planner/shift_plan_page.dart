import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import '../../app/shell.dart';

/// Plan the rest of the shift: when heavy work fits, when rotation must start, when strenuous work must stop,
/// and the UAE midday break. Crew level only; no individual data.
class ShiftPlanPage extends StatefulWidget {
  const ShiftPlanPage({super.key});
  @override
  State<ShiftPlanPage> createState() => _ShiftPlanPageState();
}

class _ShiftPlanPageState extends State<ShiftPlanPage> {
  J? plan;
  String? key;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final id = s.selectedWorksiteId;
    if (id == null) return;
    try {
      final p = jMap(await s.api.get('/planner/$id'));
      if (mounted) setState(() => (plan = p, error = null));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final visible = context.watch<NavController>().index == Nav.plan;
    // Reload when the page is opened, the site changes or the site's scenario changes (the forecast changes with it).
    final scenario = s.stationStatus(s.selectedWorksiteId ?? '')?['scenario_id'];
    final k = '${s.selectedWorksiteId}|$scenario|$visible';
    if (k != key) {
      final siteChanged = key == null || !key!.startsWith('${s.selectedWorksiteId}|');
      key = k;
      if (siteChanged) plan = null;
      if (visible || plan == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final p = plan;
    final t = Theme.of(context).textTheme;
    return PageBody(children: [
      SectionCard(
        title: p == null ? 'Shift plan' : 'Next ${p['hours']} hours at ${p['worksite_name']}',
        subtitle: 'For each crew: when heavy work fits, when a work/rest schedule must start and when strenuous work must stop. '
            'Based on the crew\'s workload, clothing and acclimatization (NIOSH limits) and the UAE midday break.',
        trailing: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Update')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Legend(),
          if (p != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.info_outline, size: 16, color: HG.muted),
              const SizedBox(width: 8),
              Expanded(child: Text('${p['note']}', style: t.bodySmall?.copyWith(color: HG.muted))),
            ]),
          ],
        ]),
      ),
      if (error != null) Text(error!, style: const TextStyle(color: HG.high)),
      if (p == null && error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (p != null)
        for (final c in jList(p['crews'])) _CrewPlan(c),
    ]);
  }
}

class _CrewPlan extends StatelessWidget {
  const _CrewPlan(this.c);
  final J c;

  static const _adviceIcon = {
    'ok': (Icons.check_circle_outline, Color(0xFF166534)),
    'warn': (Icons.schedule, Color(0xFF9A3412)),
    'stop': (Icons.do_not_disturb_on_outlined, Color(0xFF991B1B)),
    'info': (Icons.wb_sunny_outlined, Color(0xFF1E3A8A)),
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cells = jList(c['cells']);
    return SectionCard(
      title: '${c['crew_name']}',
      subtitle: '${'${c['workload']}'.replaceAll('_', ' ')} work${'${c['zone']}'.isEmpty ? '' : ' · ${c['zone']}'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in jList(c['advice']))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_adviceIcon['${a['kind']}']!.$1, size: 18, color: _adviceIcon['${a['kind']}']!.$2),
              const SizedBox(width: 10),
              Expanded(child: Text('${a['text']}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
            ]),
          ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final every = box.maxWidth / cells.length < 52 ? 2 : 1;
          return Column(children: [
            Row(children: [for (final x in cells) Expanded(child: _Cell(x))]),
            const SizedBox(height: 6),
            Row(children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  child: Text(i == 0 ? 'Now' : (i % every == 0 ? '${cells[i]['clock']}' : ''),
                      textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: HG.muted)),
                ),
            ]),
          ]);
        }),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.x);
  final J x;

  static String short(String? regime) => switch (regime) { '45_15' => '45/15', '30_30' => '30/30', '15_45' => '15/45', _ => '' };

  @override
  Widget build(BuildContext context) {
    final off = x['in_shift'] != true;
    final cat = '${x['category']}';
    final sev = Sev.of(cat);
    final stop = cat == 'critical' && x['regime'] == null;
    final midday = x['midday_break'] == true;
    final label = off ? 'Off' : stop ? 'Stop' : (x['regime'] == null ? '' : short(x['regime'] as String?));
    final tip = off
        ? '${x['clock']}: outside this crew\'s shift'
        : '${x['clock']}: ${sev.label}${x['regime'] != null ? ', needs ${short(x['regime'] as String?)} work/rest' : ''}'
            '${stop ? ', no schedule is enough' : ''}${midday ? '. UAE midday break' : ''}'
            '${x['effective_wbgt'] != null ? ' (effective WBGT ${x['effective_wbgt']} °C, continuous-work limit ${x['limit']} °C)' : ''}';
    return Tooltip(
      message: tip,
      child: Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: off ? HG.subtle : sev.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: midday ? Border.all(color: const Color(0xFF1D4ED8), width: 1.5) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          if (midday) ...[const Icon(Icons.wb_sunny_outlined, size: 12, color: Color(0xFF1D4ED8)), const SizedBox(width: 3)],
          Flexible(child: Text(label, overflow: TextOverflow.clip, softWrap: false,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: off ? HG.muted : sev.ink))),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, String text, {Color? border, IconData? icon}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 18,
            height: 14,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4), border: border == null ? null : Border.all(color: border, width: 1.5)),
            child: icon == null ? null : Icon(icon, size: 9, color: border),
          ),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12.5, color: HG.muted)),
        ]);
    return Wrap(spacing: 18, runSpacing: 8, children: [
      item(Sev.routine.color.withValues(alpha: 0.16), 'Normal work fits'),
      item(Sev.caution.color.withValues(alpha: 0.16), 'Caution: close to the limit'),
      item(Sev.elevated.color.withValues(alpha: 0.16), 'Work/rest schedule needed (e.g. 45/15)'),
      item(Sev.critical.color.withValues(alpha: 0.16), 'Stop strenuous work'),
      item(Colors.white, 'UAE midday break', border: const Color(0xFF1D4ED8), icon: Icons.wb_sunny_outlined),
      item(HG.subtle, 'Outside shift'),
    ]);
  }
}
