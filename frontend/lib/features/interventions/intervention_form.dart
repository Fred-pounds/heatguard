import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';

Future<void> showInterventionForm(BuildContext context, {Alert? alert, String? crewId}) => showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppState>(),
        child: InterventionFormDialog(alert: alert, crewId: crewId ?? (alert?.crewId == '__site__' ? null : alert?.crewId)),
      ),
    );

/// Records a protective action. Optional context changes (workload, work/rest regime)
/// are applied to the crew and the crew is reassessed immediately.
class InterventionFormDialog extends StatefulWidget {
  const InterventionFormDialog({super.key, this.alert, this.crewId});
  final Alert? alert;
  final String? crewId;
  @override
  State<InterventionFormDialog> createState() => _InterventionFormDialogState();
}

class _InterventionFormDialogState extends State<InterventionFormDialog> {
  String? crewId;
  String action = 'cooling_rest_break';
  String? newWorkload;
  String? newRegime;
  final notes = TextEditingController();
  final duration = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    crewId = widget.crewId;
    final req = widget.alert?.recommendations.where((r) => '${r['action']}'.toLowerCase().contains('rotation')).toList() ?? [];
    if (req.isNotEmpty) action = 'work_rotation';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final types = jMap(s.meta['intervention_types']);
    final crews = widget.alert == null ? s.crews : s.crews.where((c) => c.worksiteId == widget.alert!.worksiteId).toList();
    final a = crewId == null ? null : s.assessmentFor(crewId!);
    final required = a?.limit?['required_regime'] as String?;
    return AlertDialog(
      title: const Text('Record protective intervention'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (widget.alert != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: HG.bg, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  SevChip(widget.alert!.severity),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Linked to alert for ${widget.alert!.crewName} (${widget.alert!.worksiteName})', style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
            DropdownButtonFormField<String>(
              initialValue: crewId,
              decoration: const InputDecoration(labelText: 'Crew *'),
              items: [for (final c in crews) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => crewId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: action,
              decoration: const InputDecoration(labelText: 'Action taken *'),
              items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text('${e.value}'))],
              onChanged: (v) => setState(() => action = v!),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: newRegime,
                  decoration: InputDecoration(
                      labelText: 'Set work/rest regime (optional)',
                      helperText: required == null ? null : 'Assessment requires at least: ${regimeLabels[required]}'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No change')),
                    for (final e in regimeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => newRegime = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: newWorkload,
                  decoration: const InputDecoration(labelText: 'Reduce workload to (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No change')),
                    for (final w in ['rest', 'light', 'moderate', 'heavy', 'very_heavy']) DropdownMenuItem(value: w, child: Text(humanize(w))),
                  ],
                  onChanged: (v) => setState(() => newWorkload = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: duration, decoration: const InputDecoration(labelText: 'Planned duration (minutes, optional)'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (what was done, by whom, where)')),
            const SizedBox(height: 10),
            const Text(
              'The crew is reassessed immediately and follow-up assessments are recorded automatically. '
              'HeatGuard never clears a worker to resume work - that decision rests with qualified personnel.',
              style: TextStyle(fontSize: 11.5, color: HG.muted),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: HG.high))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: saving || crewId == null ? null : _save,
          icon: const Icon(Icons.healing, size: 18),
          label: Text(saving ? 'Recording...' : 'Record intervention'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    final body = {
      'alert_id': widget.alert?.id,
      'crew_id': crewId,
      'action': action,
      'notes': notes.text.trim(),
      'new_workload': newWorkload,
      'new_work_rest_regime': newRegime,
      'duration_minutes': int.tryParse(duration.text),
    };
    final err = await context.read<AppState>().run((api) => api.post('/interventions', body));
    if (!mounted) return;
    if (err != null) {
      setState(() {
        saving = false;
        error = err;
      });
      return;
    }
    Navigator.pop(context);
    showResult(context, null, 'Intervention recorded - crew reassessed');
  }
}
