import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final g = jMap(s.meta['guideline']);
    final cfg = jMap(s.meta['settings']);
    final t = Theme.of(context).textTheme;
    if (g.isEmpty) return const LoadingState(message: 'Loading configuration...');
    final limits = jMap(g['limits']);
    final policy = jMap(g['site_policy']);

    Widget section(String title, IconData icon, List<Widget> children, {bool open = false}) => Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Details(title: title, icon: icon, initiallyExpanded: open, children: children),
          ),
        );

    return PageBody(maxWidth: 960, children: [
      SectionCard(
        title: 'How HeatGuard assesses heat risk',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Each crew is compared with the NIOSH heat-exposure limit for its workload: the REL for acclimatized workers and the '
            'lower RAL for unacclimatized or unknown. The risk level shows which work/rest schedule keeps the crew within that limit. '
            'Missing or stale data is never treated as safe.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text('${g['name']} · ${g['edition']} · ${g['publication']}', style: t.bodySmall),
        ]),
      ),
      section('Risk levels', Icons.stacked_bar_chart, [
        for (final c in jList(jMap(g['risk_categories'])['categories']))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 190, child: Align(alignment: Alignment.centerLeft, child: SevChip(c['id']))),
              Expanded(child: Text('${c['rule']}', style: t.bodyMedium)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(width: 190, child: Align(alignment: Alignment.centerLeft, child: SevChip('unavailable'))),
            Expanded(child: Text('Required inputs are missing, invalid or stale. This is never read as low risk, and it raises a data alert.', style: t.bodyMedium)),
          ]),
        ),
        const SizedBox(height: 8),
        Text('Caution margin: ${policy['caution_margin_c']} °C. This is a site-policy setting, not a NIOSH value.', style: t.bodySmall),
      ], open: true),
      section('Equations and averaging', Icons.functions, [
        for (final k in ['REL', 'RAL']) KV(k, '${jMap(limits[k])['equation']}  (${jMap(limits[k])['label']})', width: 80),
        KV('Units', '${limits['units']}', width: 80),
        const SizedBox(height: 8),
        Text('${policy['averaging_note']}', style: t.bodySmall),
      ]),
      section('Workload and clothing', Icons.checkroom_outlined, [
        Text('Metabolic rate by workload', style: t.titleSmall),
        for (final e in jMap(jMap(g['metabolic_rates'])['classes']).entries) KV('${jMap(e.value)['label']} · ${jMap(e.value)['watts']} W', '${jMap(e.value)['examples']}', width: 150),
        const SizedBox(height: 12),
        Text('Clothing adjustment (added to WBGT)', style: t.titleSmall),
        for (final e in jMap(jMap(g['clothing_adjustment_factors'])['categories']).entries)
          KV(jMap(e.value)['caf'] == null ? 'Needs setup' : '+${jMap(e.value)['caf']} °C', '${jMap(e.value)['label']}', width: 150),
      ]),
      section('Acclimatization and hydration', Icons.water_drop_outlined, [
        Text('${jMap(g['acclimatization'])['schedule_new_workers']}', style: t.bodyMedium),
        const SizedBox(height: 6),
        Text('${jMap(g['acclimatization'])['schedule_experienced_workers']}', style: t.bodyMedium),
        const SizedBox(height: 6),
        Text('${g['hydration']}', style: t.bodyMedium),
      ]),
      section('Limitations', Icons.info_outline, [
        for (final l in (g['limitations'] as List? ?? [])) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $l', style: t.bodyMedium)),
      ]),
      section('Data governance', Icons.verified_user_outlined, const [
        _Principle('Data minimisation', 'Only crew-level work context and environmental data are stored. No names or health data.'),
        _Principle('Consent', 'Any future personal or physiological signal must be optional, with informed consent that can be withdrawn.'),
        _Principle('Access control', 'Supervisors see crew-level data. Workers see only their own crew\'s notice.'),
        _Principle('Non-punitive use', 'Never used for discipline, ranking or employment decisions. There is no individual scoring.'),
        _Principle('Transparency', 'Every assessment shows its data, method, missing inputs, reasons, actions and limitations.'),
        _Principle('No medical diagnosis', 'Decision support only. It does not diagnose illness or clear anyone to resume work.'),
      ]),
      section('System configuration', Icons.settings_outlined, [
        KV('Storage', humanize('${cfg['storage_backend']}'), width: 220),
        KV('Data counted as stale after', '${cfg['stale_after_seconds']} s', width: 220),
        KV('Escalate unacknowledged after', '${cfg['escalate_after_seconds']} s', width: 220),
        KV('Improvement needed for review', '${cfg['sustained_improvement_readings']} consecutive assessments', width: 220),
        KV('Simulator speed', '${cfg['tick_seconds']} s per simulated minute at 1×', width: 220),
        KV('Retention', '${jMap(cfg['retention'])['readings_per_site']} readings per site · ${jMap(cfg['retention'])['days']} days', width: 220),
        KV('API', s.api.baseUrl, width: 220),
        const SizedBox(height: 6),
        Text('Change these with backend environment variables (see backend/.env.example). Sign-in uses demo roles; replace them with Firebase Authentication before field use.',
            style: t.bodySmall),
      ]),
    ]);
  }
}

class _Principle extends StatelessWidget {
  const _Principle(this.title, this.text);
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HG.muted)),
        ]),
      );
}
