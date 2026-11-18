import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'help.dart';
import 'widgets.dart';

/// "I feel unwell / report a co-worker": choose who and what, send to the first aider.
class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key});

  static Future<void> open(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: T.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => AppScope(
          state: AppScope.of(context),
          child: Directionality(
            textDirection: AppScope.of(context).l.isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: const ReportSheet(),
          ),
        ),
      );

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  bool self = true;
  final chosen = <String>{};
  bool sending = false;
  String? result; // first_aid | emergency
  String? error;

  Future<void> _send() async {
    final s = AppScope.of(context);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      result = await s.reportSymptoms(self: self, symptoms: chosen.toList());
    } on ApiError catch (e) {
      error = e.message == 'network' ? s.l.t('cant_connect') : e.message;
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    final red = jMap(s.catalog['symptoms_red_flag']).keys.toList();
    final other = jMap(s.catalog['symptoms_first_aid']).keys.toList();

    if (result != null) return _result(context);

    Widget option(String code, {bool serious = false}) {
      final on = chosen.contains(code);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? T.navySoft : T.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: on ? T.navy : T.border, width: on ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => on ? chosen.remove(code) : chosen.add(code)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(children: [
                Icon(on ? Icons.check_box : Icons.check_box_outline_blank, color: on ? T.navy : T.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(l.t('symptom.$code'), style: TextStyle(fontSize: 15.5, fontWeight: serious ? FontWeight.w600 : FontWeight.w500))),
              ]),
            ),
          ),
        ),
      );
    }

    return Narrow(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: T.border, borderRadius: BorderRadius.circular(2))),
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 18, 20, 8), children: [
            Text(l.t('unwell_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l.t('unwell_hint'), style: const TextStyle(fontSize: 14.5, color: T.muted)),
            const SizedBox(height: 18),
            Text(l.t('who_is_unwell'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.muted)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(46), selectedBackgroundColor: T.navySoft),
                segments: [
                  ButtonSegment(value: true, label: Text(l.t('unwell_who_self')), icon: const Icon(Icons.person_outline)),
                  ButtonSegment(value: false, label: Text(l.t('unwell_who_coworker')), icon: const Icon(Icons.group_outlined)),
                ],
                selected: {self},
                onSelectionChanged: (v) => setState(() => self = v.first),
              ),
            ),
            const SizedBox(height: 20),
            Text(l.t('serious_signs'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.muted)),
            const SizedBox(height: 8),
            for (final c in red) option(c, serious: true),
            const SizedBox(height: 12),
            Text(l.t('other_signs'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.muted)),
            const SizedBox(height: 8),
            for (final c in other) option(c),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(icon: Icons.error_outline, text: error!)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: FilledButton(
            onPressed: chosen.isEmpty || sending ? null : _send,
            child: sending
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(l.t('unwell_send')),
          ),
        ),
      ]),
    );
  }

  Widget _result(BuildContext context) {
    final l = AppScope.of(context).l;
    final emergency = result == 'emergency';
    final lv = Level.of(emergency ? 'critical' : 'routine');
    return Narrow(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: emergency ? lv.tint : T.navySoft, shape: BoxShape.circle),
              child: Icon(emergency ? Icons.call : Icons.check, size: 32, color: emergency ? lv.color : T.navy),
            ),
          ),
          const SizedBox(height: 16),
          Text(l.t('report_sent'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            l.t(emergency ? 'unwell_sent_emergency' : 'unwell_sent_first_aid'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.5, color: T.text),
          ),
          const SizedBox(height: 24),
          if (emergency) ...[const CallButton(), const SizedBox(height: 10)],
          OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l.t('back'))),
        ]),
      ),
    );
  }
}
