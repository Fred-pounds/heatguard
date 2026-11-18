import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import 'settings.dart';
import 'widgets.dart';

/// Optional wearable sharing: consent, own signals, and who sees what.
class HealthTab extends StatelessWidget {
  const HealthTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Narrow(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                child: Text(l.t('health_intro'), style: const TextStyle(fontSize: 15, color: T.muted, height: 1.45)),
              ),
              if (s.unpaired && s.workerId == null) Notice(icon: Icons.link_off, text: l.t('unpaired')),
              if (s.workerId == null)
                Section(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: T.subtle, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.watch_outlined, color: T.muted),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(l.t('no_badge_health'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: () => BadgePicker.show(context), child: Text(l.t('link_badge'))),
                  ],
                )
              else if (s.me == null)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _BadgeCard(s: s, me: s.me!),
              Section(
                title: l.t('what_shared'),
                icon: Icons.privacy_tip_outlined,
                children: [
                  InfoRow(icon: Icons.health_and_safety_outlined, text: l.t('shared.1')),
                  InfoRow(icon: Icons.supervisor_account_outlined, text: l.t('shared.2')),
                  InfoRow(icon: Icons.auto_delete_outlined, text: l.t('shared.3')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatefulWidget {
  const _BadgeCard({required this.s, required this.me});
  final WorkerState s;
  final J me;
  @override
  State<_BadgeCard> createState() => _BadgeCardState();
}

class _BadgeCardState extends State<_BadgeCard> {
  String? band;
  bool busy = false;

  Future<void> _consent(bool granted) async {
    setState(() => busy = true);
    try {
      await widget.s.setConsent(granted, ageBand: granted ? band : null);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.l.t('cant_connect'))));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = s.l;
    final me = widget.me;
    final granted = jMap(me['consent'])['status'] == 'granted';
    final sig = jMap(me['signal']);
    band ??= me['age_band'] as String?;
    final check = sig['status'] == 'check';

    return Section(
      title: '${l.t('badge')} ${me['badge'] ?? s.badge ?? ''}',
      icon: Icons.watch_outlined,
      trailing: TextButton(onPressed: () => BadgePicker.show(context), child: Text(l.t('change'))),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: granted ? Pill(l.t('consent_on'), color: T.ok, tint: const Color(0xFFE7F6EF)) : Pill(l.t('consent_off')),
        ),
        const SizedBox(height: 16),
        if (granted) ...[
          if (sig.isNotEmpty) ...[
            Row(
              children: [
                _Metric(
                  label: l.t('heart_rate'),
                  value: sig['heart_rate'] == null ? '–' : '${(sig['heart_rate'] as num).round()}',
                  unit: 'bpm',
                  sub: sig['hr_limit'] == null ? null : fill(l.t('your_limit'), {'v': sig['hr_limit']}),
                ),
                const SizedBox(width: 10),
                _Metric(
                  label: l.t('body_temp'),
                  value: sig['core_temp_est'] == null ? '–' : (sig['core_temp_est'] as num).toStringAsFixed(1),
                  unit: '°C',
                  sub: sig['core_limit'] == null ? null : fill(l.t('your_limit'), {'v': '${sig['core_limit']} °C'}),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Metric(
                  label: l.t('badge_battery'),
                  value: sig['battery_pct'] == null ? '–' : '${(sig['battery_pct'] as num).round()}',
                  unit: '%',
                ),
                const SizedBox(width: 10),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Notice(
            icon: check ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            text: check ? l.t('my_status_check') : l.t('my_status_ok'),
            color: check ? Level.of('high').color : T.ok,
            tint: check ? Level.of('high').tint : const Color(0xFFE7F6EF),
          ),
          OutlinedButton(onPressed: busy ? null : () => _consent(false), child: Text(l.t('consent_stop'))),
        ] else ...[
          Text(l.t('consent_body'), style: const TextStyle(fontSize: 14.5, color: T.text, height: 1.5)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: band,
            decoration: InputDecoration(labelText: l.t('consent_age')),
            items: [for (final b in (s.catalog['age_bands'] as List? ?? [])) DropdownMenuItem(value: '$b', child: Text('$b'))],
            onChanged: (v) => setState(() => band = v),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: busy || band == null ? null : () => _consent(true), child: Text(l.t('consent_share'))),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit, this.sub});
  final String label;
  final String value;
  final String unit;
  final String? sub;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: T.subtle, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            style: const TextStyle(fontSize: 12.5, color: T.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: T.text),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 13, color: T.muted),
                ),
              ],
            ),
          ),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: T.muted)),
        ],
      ),
    ),
  );
}
