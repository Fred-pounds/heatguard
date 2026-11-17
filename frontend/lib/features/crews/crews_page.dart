import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';

const workloadIds = ['rest', 'light', 'moderate', 'heavy', 'very_heavy', 'unknown'];
const acclIds = ['acclimatized', 'not_acclimatized', 'unknown'];

class CrewsPage extends StatelessWidget {
  const CrewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return PageBody(children: [
      SectionCard(
        title: 'Crews',
        subtitle: 'Crew-level operational context only - no worker names or individual health data are collected.',
        trailing: FilledButton.icon(
          onPressed: s.dataIsLive ? () => showCrewForm(context, null) : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add crew'),
        ),
        child: s.crews.isEmpty
            ? const EmptyState(icon: Icons.groups_outlined, title: 'No crews registered', message: 'Add a crew to start assessments.')
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingTextStyle: Theme.of(context).textTheme.labelSmall,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 60,
                  columns: const [
                    DataColumn(label: Text('CREW')),
                    DataColumn(label: Text('WORKSITE / ZONE')),
                    DataColumn(label: Text('WORKERS'), numeric: true),
                    DataColumn(label: Text('WORKLOAD')),
                    DataColumn(label: Text('ACCLIMATIZATION')),
                    DataColumn(label: Text('CLOTHING')),
                    DataColumn(label: Text('WORK/REST')),
                    DataColumn(label: Text('SHIFT')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [for (final c in s.crews) _row(context, s, c)],
                ),
              ),
      ),
      _WorkloadReference(meta: s.meta),
    ]);
  }

  DataRow _row(BuildContext context, AppState s, Crew c) {
    final ws = s.worksiteById(c.worksiteId);
    Future<void> quick(String field, String value, String label) async {
      final err = await s.run((api) => api.put('/crews/${c.id}', {field: value}));
      if (context.mounted) showResult(context, err, '${c.name}: $label updated - reassessed');
    }

    Widget inline(String field, String value, List<String> ids) => DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: ValueKey('${c.id}-$field-$value'),
            value: value,
            isDense: true,
            style: TextStyle(
                fontSize: 12.5,
                color: value == 'unknown' || value == 'not_acclimatized' ? HG.elevated : HG.text,
                fontWeight: FontWeight.w600),
            items: [for (final id in ids) DropdownMenuItem(value: id, child: Text(humanize(id)))],
            onChanged: s.dataIsLive ? (v) => v == null || v == value ? null : quick(field, v, humanize(field)) : null,
          ),
        );

    return DataRow(cells: [
      DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(c.task.isEmpty ? '-' : c.task, style: const TextStyle(fontSize: 11, color: HG.muted), overflow: TextOverflow.ellipsis),
      ])),
      DataCell(Text('${ws?.name.split(' ').take(2).join(' ') ?? c.worksiteId}\n${c.zone}', style: const TextStyle(fontSize: 12))),
      DataCell(Text('${c.workerCount}')),
      DataCell(inline('workload', c.workload, workloadIds)),
      DataCell(inline('acclimatization', c.acclimatization, acclIds)),
      DataCell(Text(_clothingLabel(s, c.clothing), style: const TextStyle(fontSize: 12))),
      DataCell(Text(regimeLabels[c.regime] ?? c.regime, style: const TextStyle(fontSize: 12))),
      DataCell(Text('${c.shiftStart} · ${c.shiftHours.toStringAsFixed(c.shiftHours % 1 == 0 ? 0 : 1)} h', style: const TextStyle(fontSize: 12))),
      DataCell(SevChip(s.assessmentFor(c.id)?.category)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Edit crew', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: s.dataIsLive ? () => showCrewForm(context, c) : null),
        IconButton(
          tooltip: 'Remove crew',
          icon: const Icon(Icons.delete_outline, size: 19, color: HG.high),
          onPressed: !s.dataIsLive
              ? null
              : () async {
                  final ok = await confirmDialog(context,
                      title: 'Remove ${c.name}?',
                      message: 'The crew will no longer be assessed. Alert and intervention history is preserved. '
                          'Crews with unresolved alerts cannot be removed.',
                      confirm: 'Remove',
                      destructive: true);
                  if (!ok) return;
                  final err = await s.run((api) => api.delete('/crews/${c.id}'));
                  if (context.mounted) showResult(context, err, '${c.name} removed');
                },
        ),
      ])),
    ]);
  }
}

String _clothingLabel(AppState s, String id) {
  final m = jMap(jMap(s.meta['clothing'])[id]);
  if (m.isEmpty) return humanize(id);
  final caf = m['caf'];
  return '${m['label']}${caf == null ? ' (needs config)' : (caf as num) > 0 ? ' (+$caf)' : ''}';
}

Future<void> showCrewForm(BuildContext context, Crew? crew) =>
    showDialog(context: context, builder: (_) => ChangeNotifierProvider.value(value: context.read<AppState>(), child: CrewFormDialog(crew: crew)));

class CrewFormDialog extends StatefulWidget {
  const CrewFormDialog({super.key, this.crew});
  final Crew? crew;
  @override
  State<CrewFormDialog> createState() => _CrewFormDialogState();
}

class _CrewFormDialogState extends State<CrewFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, workers, task, shiftStart, shiftHours;
  late String worksiteId, zone, workload, clothing, accl, regime;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final c = widget.crew;
    final ws = c == null ? s.selectedWorksite! : s.worksiteById(c.worksiteId)!;
    name = TextEditingController(text: c?.name ?? '');
    workers = TextEditingController(text: '${c?.workerCount ?? 5}');
    task = TextEditingController(text: c?.task ?? '');
    shiftStart = TextEditingController(text: c?.shiftStart ?? '07:00');
    shiftHours = TextEditingController(text: '${c?.shiftHours ?? 8}');
    worksiteId = ws.id;
    zone = c?.zone ?? ws.zones.first;
    workload = c?.workload ?? 'unknown';
    clothing = c?.clothing ?? 'standard_work_clothing';
    accl = c?.acclimatization ?? 'unknown';
    regime = c?.regime ?? 'continuous';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ws = s.worksiteById(worksiteId)!;
    final workloads = jMap(s.meta['workloads']);
    final clothingOpts = jMap(s.meta['clothing']);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    Widget field(Widget w) => SizedBox(width: narrow ? double.infinity : 290, child: w);

    return AlertDialog(
      title: Text(widget.crew == null ? 'Add crew' : 'Edit ${widget.crew!.name}'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 14, runSpacing: 14, children: [
                field(TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Crew name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                )),
                field(TextFormField(
                  controller: workers,
                  decoration: const InputDecoration(labelText: 'Number of workers *'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 500 ? '1-500' : null;
                  },
                )),
                field(DropdownButtonFormField<String>(
                  initialValue: worksiteId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Worksite'),
                  items: [for (final w in s.worksites) DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() {
                    worksiteId = v!;
                    zone = s.worksiteById(v)!.zones.first;
                  }),
                )),
                field(DropdownButtonFormField<String>(
                  key: ValueKey('zone-$worksiteId'),
                  initialValue: zone,
                  decoration: const InputDecoration(labelText: 'Work zone'),
                  items: [for (final z in ws.zones) DropdownMenuItem(value: z, child: Text(z))],
                  onChanged: (v) => setState(() => zone = v!),
                )),
                field(DropdownButtonFormField<String>(
                  initialValue: workload,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Workload category', helperText: 'Metabolic class used for the limit'),
                  items: [
                    for (final e in workloads.entries)
                      DropdownMenuItem(value: e.key, child: Text('${jMap(e.value)['label']} (~${jMap(e.value)['watts']} W)')),
                    const DropdownMenuItem(value: 'unknown', child: Text('Unknown (assessment incomplete)')),
                  ],
                  onChanged: (v) => setState(() => workload = v!),
                )),
                field(DropdownButtonFormField<String>(
                  initialValue: accl,
                  decoration: const InputDecoration(labelText: 'Acclimatization', helperText: 'Unknown is treated conservatively (RAL)'),
                  items: [for (final a in acclIds) DropdownMenuItem(value: a, child: Text(humanize(a)))],
                  onChanged: (v) => setState(() => accl = v!),
                )),
                field(DropdownButtonFormField<String>(
                  initialValue: clothing,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Clothing / PPE', helperText: 'Clothing adjustment added to WBGT'),
                  items: [
                    for (final e in clothingOpts.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text('${jMap(e.value)['label']} ${jMap(e.value)['caf'] == null ? '(requires configuration)' : '(+${jMap(e.value)['caf']} °C)'}',
                            overflow: TextOverflow.ellipsis),
                      ),
                    const DropdownMenuItem(value: 'unknown', child: Text('Unknown (assessment incomplete)')),
                  ],
                  onChanged: (v) => setState(() => clothing = v!),
                )),
                field(DropdownButtonFormField<String>(
                  initialValue: regime,
                  decoration: const InputDecoration(labelText: 'Work/rest regime (per hour)'),
                  items: [for (final e in regimeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => regime = v!),
                )),
                field(TextFormField(
                  controller: shiftStart,
                  decoration: const InputDecoration(labelText: 'Shift start (HH:MM)'),
                  validator: (v) => RegExp(r'^\d{2}:\d{2}$').hasMatch(v ?? '') ? null : 'Use HH:MM',
                )),
                field(TextFormField(
                  controller: shiftHours,
                  decoration: const InputDecoration(labelText: 'Shift duration (hours)'),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || n <= 0 || n > 16 ? '0-16' : null;
                  },
                )),
                SizedBox(
                  width: narrow ? double.infinity : 594,
                  child: TextFormField(controller: task, decoration: const InputDecoration(labelText: 'Current task')),
                ),
              ]),
              if (clothing == 'specialized_ppe' || clothing == 'vapor_barrier_coveralls')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${jMap(clothingOpts[clothing])['note']}', style: const TextStyle(color: HG.elevated, fontSize: 12)),
                ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: HG.high))),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Saving...' : 'Save crew')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final body = {
      'name': name.text.trim(),
      'worksite_id': worksiteId,
      'zone': zone,
      'worker_count': int.parse(workers.text),
      'workload': workload,
      'clothing': clothing,
      'acclimatization': accl,
      'work_rest_regime': regime,
      'shift_start': shiftStart.text,
      'shift_duration_hours': double.parse(shiftHours.text),
      'current_task': task.text.trim(),
    };
    final s = context.read<AppState>();
    final err = await s.run((api) => widget.crew == null ? api.post('/crews', body) : api.put('/crews/${widget.crew!.id}', body));
    if (!mounted) return;
    if (err != null) {
      setState(() {
        saving = false;
        error = err;
      });
      return;
    }
    Navigator.pop(context);
    showResult(context, null, widget.crew == null ? 'Crew added and assessed' : 'Crew updated and reassessed');
  }
}

class _WorkloadReference extends StatelessWidget {
  const _WorkloadReference({required this.meta});
  final J meta;
  @override
  Widget build(BuildContext context) {
    final wl = jMap(meta['workloads']);
    final cl = jMap(meta['clothing']);
    return SectionCard(
      title: 'Reference: workload and clothing categories',
      subtitle: 'From the configured guideline. Values are documented category estimates, not measurements.',
      child: Wrap(spacing: 32, runSpacing: 16, children: [
        SizedBox(
          width: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Workload (metabolic rate)', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in wl.entries)
              KV('${jMap(e.value)['label']} · ${jMap(e.value)['watts']} W', '${jMap(e.value)['examples']}', width: 150),
          ]),
        ),
        SizedBox(
          width: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Clothing adjustment factor (°C-WBGT)', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in cl.entries)
              KV('${jMap(e.value)['caf'] ?? 'requires config'}', '${jMap(e.value)['label']}', width: 110),
          ]),
        ),
      ]),
    );
  }
}
