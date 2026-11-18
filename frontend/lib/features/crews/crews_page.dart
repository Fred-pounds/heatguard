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
    final t = Theme.of(context).textTheme;
    return PageBody(children: [
      Row(children: [
        Expanded(
          child: Text('Crew-level work context only. No worker names or health data are collected.',
              style: t.bodyLarge?.copyWith(color: HG.muted)),
        ),
        FilledButton.icon(
          onPressed: s.dataIsLive ? () => showCrewForm(context, null) : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add crew'),
        ),
      ]),
      Card(
        child: s.crews.isEmpty
            ? const EmptyState(icon: Icons.groups_outlined, title: 'No crews yet', message: 'Add a crew to start assessments.')
            : LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth > 900;
                return Column(children: [
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text('Crew', style: t.labelMedium)),
                        Expanded(flex: 2, child: Text('Workload', style: t.labelMedium)),
                        Expanded(flex: 2, child: Text('Acclimatization', style: t.labelMedium)),
                        Expanded(flex: 2, child: Text('Clothing', style: t.labelMedium)),
                        Expanded(flex: 2, child: Text('Work / rest', style: t.labelMedium)),
                        SizedBox(width: 150, child: Text('Status', style: t.labelMedium)),
                        const SizedBox(width: 48),
                      ]),
                    ),
                  for (var i = 0; i < s.crews.length; i++) ...[
                    if (i > 0 || wide) const Divider(),
                    _CrewRow(crew: s.crews[i], wide: wide),
                  ],
                ]);
              }),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Details(title: 'Reference: workload and clothing categories', icon: Icons.menu_book_outlined, children: [_WorkloadReference(meta: s.meta)]),
        ),
      ),
    ]);
  }
}

class _CrewRow extends StatelessWidget {
  const _CrewRow({required this.crew, required this.wide});
  final Crew crew;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final c = crew;
    final ws = s.worksiteById(c.worksiteId);
    Text warn(String v, String label) =>
        Text(label, style: TextStyle(fontSize: 14, color: v == 'unknown' || v == 'not_acclimatized' ? const Color(0xFF9A3412) : HG.text));
    final menu = PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, color: HG.muted),
      enabled: s.dataIsLive,
      onSelected: (v) async {
        if (v == 'edit') showCrewForm(context, c);
        if (v == 'delete') {
          final ok = await confirmDialog(context,
              title: 'Remove ${c.name}?',
              message: 'The crew will no longer be assessed. Its alert and intervention history is kept. Crews with unresolved alerts cannot be removed.',
              confirm: 'Remove',
              destructive: true);
          if (!ok) return;
          final err = await s.run((api) => api.delete('/crews/${c.id}'));
          if (context.mounted) showResult(context, err, '${c.name} removed');
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit crew')),
        PopupMenuItem(value: 'delete', child: Text('Remove crew', style: TextStyle(color: HG.high))),
      ],
    );
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text('${ws?.name.split(' ').take(2).join(' ') ?? ''} · ${c.zone} · ${c.workerCount} workers', style: t.bodySmall),
    ]);
    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              name,
              const SizedBox(height: 6),
              Text('${humanize(c.workload)} work · ${humanize(c.acclimatization)} · ${regimeLabels[c.regime]}', style: t.bodySmall),
            ]),
          ),
          SevChip(s.assessmentFor(c.id)?.category, short: true),
          menu,
        ]),
      );
    }
    return InkWell(
      onTap: s.dataIsLive ? () => showCrewForm(context, c) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
        child: Row(children: [
          Expanded(flex: 3, child: name),
          Expanded(flex: 2, child: warn(c.workload, humanize(c.workload))),
          Expanded(flex: 2, child: warn(c.acclimatization, humanize(c.acclimatization))),
          Expanded(flex: 2, child: Text(_clothingShort(s, c.clothing), style: const TextStyle(fontSize: 14))),
          Expanded(flex: 2, child: Text(regimeLabels[c.regime] ?? c.regime, style: const TextStyle(fontSize: 14))),
          SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: SevChip(s.assessmentFor(c.id)?.category, short: true))),
          SizedBox(width: 48, child: menu),
        ]),
      ),
    );
  }
}

String _clothingShort(AppState s, String id) {
  if (id == 'unknown') return 'Unknown';
  final m = jMap(jMap(s.meta['clothing'])[id]);
  if (m.isEmpty) return humanize(id);
  final label = '${m['label']}'.replaceAll(RegExp(r'\s*\(.*\)'), '');
  final caf = m['caf'];
  return caf == null ? '$label (needs setup)' : ((caf as num) > 0 ? '$label (+$caf °C)' : label);
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
    return TwoColumn(
      left: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Workload (metabolic rate)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final e in wl.entries) KV('${jMap(e.value)['label']} · ${jMap(e.value)['watts']} W', '${jMap(e.value)['examples']}', width: 140),
      ]),
      right: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Clothing adjustment (added to WBGT)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final e in cl.entries) KV(jMap(e.value)['caf'] == null ? 'Needs setup' : '+${jMap(e.value)['caf']} °C', '${jMap(e.value)['label']}', width: 110),
      ]),
    );
  }
}
