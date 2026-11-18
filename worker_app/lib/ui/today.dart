import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../l10n/strings.dart';
import 'report.dart';
import 'widgets.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    final n = s.notice;
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Narrow(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!s.online) Notice(icon: Icons.cloud_off_outlined, text: l.t('offline')),
            if (n == null)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else ...[
              _StatusCard(s: s, n: n),
              if (n['midday_break'] == true)
                Notice(icon: Icons.wb_sunny_outlined, text: l.t('midday_break'), color: T.navy, tint: T.navySoft),
              _DoNow(s: s, n: n),
              const _UnwellCard(),
              if (jList(n['active_protective_actions']).isNotEmpty)
                Section(title: l.t('in_place'), icon: Icons.verified_user_outlined, children: [
                  for (final a in jList(n['active_protective_actions']))
                    InfoRow(
                      icon: Icons.check,
                      color: T.ok,
                      tint: const Color(0xFFE7F6EF),
                      text: l.or('action.${a['action']}', '${a['action_label']}'),
                      sub: fill(l.t('last_update'), {'time': hhmm(a['start_time'])}),
                    ),
                ]),
            ],
            const SizedBox(height: 8),
            _Footer(text: l.t('privacy')),
          ]),
        ),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.s, required this.n});
  final WorkerState s;
  final J n;

  @override
  Widget build(BuildContext context) {
    final l = s.l;
    final cat = '${n['category']}';
    final lv = Level.of(cat);
    final stale = !s.online;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: T.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.t('heat_level_now'), style: const TextStyle(fontSize: 13.5, color: T.muted, fontWeight: FontWeight.w600))),
          stale
              ? Pill(l.t('offline_short'), color: T.warn, tint: const Color(0xFFFEF6EE))
              : Pill(l.t('live'), color: T.ok, tint: const Color(0xFFE7F6EF)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: lv.tint, borderRadius: BorderRadius.circular(16)),
            child: Icon(lv.icon, color: lv.color, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(l.t('level.$cat'),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: T.text, height: 1.1, letterSpacing: -0.4)),
          ),
        ]),
        const SizedBox(height: 18),
        _LevelMeter(level: lv, l: l),
        const SizedBox(height: 18),
        Text(l.t('${n['message_key']}'), style: const TextStyle(fontSize: 17, height: 1.5, color: T.text, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.schedule, size: 16, color: T.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                fill(l.t('last_update'), {'time': hhmm(n['updated_at'])}),
                if (n['sim_clock'] != null) fill(l.t('site_time'), {'time': '${n['sim_clock']} GST'}),
              ].join('  ·  '),
              style: const TextStyle(fontSize: 13, color: T.muted),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Five-step scale so the level is understood at a glance, without relying on colour alone.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.l});
  final Level level;
  final L10n l;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l.t('level_scale'),
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < Level.scale.length; i++)
            Expanded(
              child: Container(
                height: 8,
                margin: EdgeInsetsDirectional.only(end: i < Level.scale.length - 1 ? 5 : 0),
                decoration: BoxDecoration(
                  color: i <= level.rank ? level.color : T.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(l.t('level.routine'), style: const TextStyle(fontSize: 12, color: T.muted)),
          const Spacer(),
          Text(l.t('level.critical'), style: const TextStyle(fontSize: 12, color: T.muted)),
        ]),
      ]),
    );
  }
}

class _DoNow extends StatelessWidget {
  const _DoNow({required this.s, required this.n});
  final WorkerState s;
  final J n;

  @override
  Widget build(BuildContext context) {
    final l = s.l;
    final cat = '${n['category']}';
    final rows = <Widget>[
      if (n['water_reminder'] == true || cat == 'routine') InfoRow(icon: Icons.water_drop_outlined, text: l.t('water')),
      if (n['work_rest'] != null)
        InfoRow(
          icon: Icons.timelapse,
          text: l.or('regime.${n['work_rest_id']}', '${n['work_rest']}'),
          sub: l.t('work_rest'),
        ),
      for (final a in jList(n['actions']))
        InfoRow(icon: Icons.check_circle_outline, text: l.or('${a['key']}', '${a['action']}')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Section(title: l.t('do_now'), children: rows);
  }
}

class _UnwellCard extends StatelessWidget {
  const _UnwellCard();
  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).l;
    return Section(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: T.navySoft, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.medical_services_outlined, color: T.navy),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('unwell_card_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l.t('unwell_card_body'), style: const TextStyle(fontSize: 14, color: T.muted, height: 1.4)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => ReportSheet.open(context),
        icon: const Icon(Icons.medical_services_outlined),
        label: Text(l.t('unwell_button')),
      ),
    ]);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).l;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 14, color: T.muted),
          const SizedBox(width: 6),
          Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: T.muted))),
        ]),
        const SizedBox(height: 6),
        Text(l.t('demo_notice'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: T.muted)),
      ]),
    );
  }
}
