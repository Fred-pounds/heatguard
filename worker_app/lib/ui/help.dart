import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'report.dart';
import 'widgets.dart';

/// Emergency tab: call 998, warning signs and first steps. Works even if the server is unreachable.
class HelpTab extends StatelessWidget {
  const HelpTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    final red = jMap(s.catalog['symptoms_red_flag']).keys.toList();
    final signs = red.isEmpty ? const ['confusion', 'collapse', 'hot_dry_skin', 'seizure'] : red;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Narrow(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CallButton(),
          const SizedBox(height: 14),
          Section(title: l.t('signs_title'), icon: Icons.warning_amber_rounded, children: [
            for (final c in signs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: T.text, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.t('symptom.$c'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
          Section(title: l.t('steps_title'), icon: Icons.healing_outlined, children: [
            for (var i = 1; i <= 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: T.navySoft, shape: BoxShape.circle),
                    child: Text('$i', style: const TextStyle(fontWeight: FontWeight.w700, color: T.navy)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(l.t('step.$i'), style: const TextStyle(fontSize: 15.5, height: 1.45)),
                    ),
                  ),
                ]),
              ),
          ]),
          OutlinedButton.icon(
            onPressed: () => ReportSheet.open(context),
            icon: const Icon(Icons.medical_services_outlined),
            label: Text(l.t('unwell_button')),
          ),
        ]),
      ),
    ]);
  }
}

/// One-tap call to the UAE ambulance number.
class CallButton extends StatelessWidget {
  const CallButton({super.key});

  Future<void> _call(BuildContext context) async {
    final l = AppScope.of(context).l;
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: '998'));
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('call_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).l;
    final c = Level.of('critical');
    return Material(
      color: c.color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _call(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: const Icon(Icons.call, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('call_998'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                Text(l.t('call_998_sub'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}
