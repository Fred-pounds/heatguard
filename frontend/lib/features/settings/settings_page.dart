import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/severity.dart';
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
    if (g.isEmpty) return const LoadingState(message: 'Loading configuration...');
    final limits = jMap(g['limits']);
    final policy = jMap(g['site_policy']);
    final mono = const TextStyle(fontFamily: 'Roboto', fontFeatures: [FontFeature.tabularFigures()], fontSize: 12.5);

    return PageBody(children: [
      SectionCard(
        title: 'Assessment guideline',
        subtitle: 'Configured in backend/app/guidelines/${g['id']}.json - values are documented, not invented.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KV('Guideline', '${g['name']}'),
          KV('Edition', '${g['edition']}'),
          KV('Publication', '${g['publication']}'),
          KV('Licence', '${g['license']}'),
          KV('Source', '${g['url']}'),
          const SizedBox(height: 10),
          Text('Exposure limits (${limits['units']})', style: Theme.of(context).textTheme.titleSmall),
          for (final k in ['REL', 'RAL']) Text('${jMap(limits[k])['equation']}    - ${jMap(limits[k])['label']}', style: mono),
          const SizedBox(height: 8),
          Text('Effective WBGT = max(latest WBGT, 60-min mean) + clothing adjustment factor', style: mono),
          Text('1-h TWA metabolic rate = (work_min × M_work + rest_min × M_rest) / 60', style: mono),
        ]),
      ),
      SectionCard(
        title: 'Risk categories',
        subtitle: '${jMap(g['risk_categories'])['source']}',
        child: Column(children: [
          for (final c in jList(jMap(g['risk_categories'])['categories']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 170, child: Align(alignment: Alignment.centerLeft, child: SevChip(c['id']))),
                Expanded(child: Text('${c['rule']}', style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 170, child: Align(alignment: Alignment.centerLeft, child: SevChip(Sev.unavailable.id))),
              const Expanded(
                child: Text('Required inputs missing, invalid or stale. Never interpreted as low risk; raises a data-quality alert.',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
          const Divider(height: 20),
          KV('Caution margin', '${policy['caution_margin_c']} °C - ${policy['caution_margin_source']}', width: 170),
          KV('Averaging', '${policy['averaging_note']}', width: 170),
        ]),
      ),
      LayoutBuilder(builder: (context, box) {
        final wl = SectionCard(
          title: 'Metabolic rate classes',
          subtitle: '${jMap(g['metabolic_rates'])['source']}',
          child: Column(children: [
            for (final e in jMap(jMap(g['metabolic_rates'])['classes']).entries)
              KV('${jMap(e.value)['label']} - ${jMap(e.value)['watts']} W', '${jMap(e.value)['examples']}', width: 150),
          ]),
        );
        final cl = SectionCard(
          title: 'Clothing adjustment factors',
          subtitle: '${jMap(g['clothing_adjustment_factors'])['source']}',
          child: Column(children: [
            for (final e in jMap(jMap(g['clothing_adjustment_factors'])['categories']).entries)
              KV(jMap(e.value)['caf'] == null ? 'requires configuration' : '+${jMap(e.value)['caf']} °C', '${jMap(e.value)['label']}', width: 150),
          ]),
        );
        if (box.maxWidth < 900) return Column(children: [wl, const SizedBox(height: 16), cl]);
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: wl), const SizedBox(width: 16), Expanded(child: cl)]));
      }),
      SectionCard(
        title: 'Acclimatization & hydration guidance',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${jMap(g['acclimatization'])['schedule_new_workers']}', style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 4),
          Text('${jMap(g['acclimatization'])['schedule_experienced_workers']}', style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 4),
          Text('${jMap(g['acclimatization'])['unknown']?['note'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${g['hydration']}', style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
      SectionCard(
        title: 'Limitations',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in (g['limitations'] as List? ?? [])) Text('• $l', style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
      SectionCard(
        title: 'Responsible data governance',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          _Principle(Icons.compress, 'Data minimisation', 'Only crew-level operational context and environmental measurements are collected. No worker names or health data in this version.'),
          _Principle(Icons.how_to_reg, 'Consent', 'Any future personal or physiological signal must be optional and require meaningful, revocable informed consent.'),
          _Principle(Icons.lock_outline, 'Access control', 'Supervisors see crew-level information. Workers see only their own crew\'s notice. Individual health data (future) would need much stricter controls.'),
          _Principle(Icons.gavel, 'Non-punitive use', 'Heat-risk information must never be used for discipline, ranking or unrelated employment decisions. There is no individual performance scoring.'),
          _Principle(Icons.visibility_outlined, 'Transparency', 'Every assessment shows the data used, method, missing information, contributing factors, recommendations and limitations.'),
          _Principle(Icons.medical_services_outlined, 'No medical diagnosis', 'HeatGuard is decision support. It does not diagnose heat illness, predict medical outcomes or clear anyone to resume work.'),
        ]),
      ),
      SectionCard(
        title: 'System configuration',
        subtitle: 'Set through backend environment variables (see backend/.env.example).',
        child: Column(children: [
          KV('Storage backend', humanize('${cfg['storage_backend']}'), width: 220),
          KV('Stale-data threshold', '${cfg['stale_after_seconds']} s', width: 220),
          KV('Escalate unacknowledged after', '${cfg['escalate_after_seconds']} s', width: 220),
          KV('Sustained improvement for review', '${cfg['sustained_improvement_readings']} consecutive assessments', width: 220),
          KV('Simulator tick', '${cfg['tick_seconds']} s per simulated minute (at 1× speed)', width: 220),
          KV('Retention', 'readings/site ${jMap(cfg['retention'])['readings_per_site']} · assessments ${jMap(cfg['retention'])['assessments']} · policy ${jMap(cfg['retention'])['days']} days', width: 220),
          KV('API endpoint', s.api.baseUrl, width: 220),
          const KV('Authentication', 'Demo roles via X-HeatGuard-Role header (supervisor / worker / admin). Replace with Firebase Authentication before field use.', width: 220),
        ]),
      ),
    ]);
  }
}

class _Principle extends StatelessWidget {
  const _Principle(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: HG.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(text, style: const TextStyle(fontSize: 12.5, color: HG.muted)),
            ]),
          ),
        ]),
      );
}

