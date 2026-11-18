import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/app_state.dart';
import 'assessment_panel.dart';
import 'common.dart';

/// Opens a crew's live assessment in a side sheet (keeps list pages uncluttered).
Future<void> showCrewAssessment(BuildContext context, String crewId) {
  final state = context.read<AppState>();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => ChangeNotifierProvider.value(
      value: state,
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(320, 620).toDouble(),
            height: double.infinity,
            child: _Sheet(crewId: crewId),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, anim, _, child) =>
        SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)), child: child),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.crewId});
  final String crewId;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final crew = s.crewById(crewId);
    final a = s.assessmentFor(crewId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HG.border))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(crew?.name ?? 'Crew', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                crew == null
                    ? ''
                    : '${crew.zone} · ${crew.workerCount} workers · ${humanize(crew.workload)} work · ${humanize(crew.acclimatization)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Expanded(
        child: a == null
            ? const EmptyState(icon: Icons.hourglass_empty, title: 'Waiting for the first assessment')
            : ListView(padding: const EdgeInsets.all(24), children: [
                AssessmentPanel(a),
                const SizedBox(height: 8),
                Text('Updated ${ago(a.timestamp)}', style: Theme.of(context).textTheme.bodySmall),
              ]),
      ),
    ]);
  }
}
