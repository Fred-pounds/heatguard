import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/speak.dart';
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
    // At High and above, what to do comes straight after the level; the midday notice follows.
    final urgent = n != null && Level.of('${n['category']}').rank >= 3;
    final midday = n != null && n['midday_break'] == true
        ? Notice(icon: Icons.wb_sunny_outlined, text: l.t('midday_break'), color: T.navy, tint: T.navySoft)
        : null;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: s.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Narrow(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!s.online) Notice(icon: Icons.cloud_off_outlined, text: l.t('offline')),
                      if (n == null)
                        const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        _StatusCard(s: s, n: n),
                        if (!urgent) ?midday,
                        _DoNow(s: s, n: n),
                        if (urgent) ?midday,
                        if (jList(n['active_protective_actions']).isNotEmpty)
                          Section(
                            title: l.t('in_place'),
                            icon: Icons.verified_user_outlined,
                            children: [
                              for (final a in jList(n['active_protective_actions']))
                                InfoRow(
                                  icon: Icons.check,
                                  color: T.ok,
                                  tint: const Color(0xFFE7F6EF),
                                  text: l.or('action.${a['action']}', '${a['action_label']}'),
                                  sub: fill(l.t('last_update'), {'time': hhmm(a['start_time'])}),
                                ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 8),
                      _Footer(text: l.t('privacy')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const _UnwellBar(),
      ],
    );
  }
}

/// Always visible above the tab bar, so reporting never needs scrolling.
class _UnwellBar extends StatelessWidget {
  const _UnwellBar();
  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).l;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: T.bg,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: Narrow(
        child: FilledButton.icon(
          onPressed: () => ReportSheet.open(context),
          icon: const Icon(Icons.medical_services_outlined),
          label: Text(l.t('unwell_button'), maxLines: 2, textAlign: TextAlign.center),
        ),
      ),
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
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: T.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.t('heat_level_now'),
                  style: const TextStyle(fontSize: 13.5, color: T.muted, fontWeight: FontWeight.w600),
                ),
              ),
              if (Speaker.supported) ...[_ListenButton(s: s, n: n), const SizedBox(width: 6)],
              stale
                  ? Pill(l.t('offline_short'), color: T.warn, tint: const Color(0xFFFEF6EE))
                  : Pill(l.t('live'), color: T.ok, tint: const Color(0xFFE7F6EF)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: lv.tint, borderRadius: BorderRadius.circular(16)),
                child: Icon(lv.icon, color: lv.color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l.t('level.$cat'),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: T.text, height: 1.1, letterSpacing: -0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _LevelMeter(level: lv, l: l),
          const SizedBox(height: 18),
          Text(
            l.t('${n['message_key']}'),
            style: const TextStyle(fontSize: 17, height: 1.5, color: T.text, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }
}

/// Reads the level, message and actions aloud in the worker's language (helps workers who read with difficulty).
class _ListenButton extends StatefulWidget {
  const _ListenButton({required this.s, required this.n});
  final WorkerState s;
  final J n;
  @override
  State<_ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<_ListenButton> {
  bool on = false;

  String _script() {
    final l = widget.s.l;
    final n = widget.n;
    final cat = '${n['category']}';
    return [
      '${l.t('heat_level_now')}: ${l.t('level.$cat')}.',
      l.t('${n['message_key']}'),
      if (n['midday_break'] == true) l.t('midday_break'),
      if (n['water_reminder'] == true || cat == 'routine') l.t('water'),
      if (n['work_rest'] != null) '${l.t('work_rest')}: ${l.or('regime.${n['work_rest_id']}', '${n['work_rest']}')}.',
      for (final a in jList(n['actions'])) '${l.or('${a['key']}', '${a['action']}')}.',
    ].join(' ');
  }

  void _toggle() {
    if (on) {
      Speaker.stop();
      setState(() => on = false);
      return;
    }
    final ok = Speaker.speak(
      _script(),
      widget.s.lang,
      onDone: () {
        if (mounted) setState(() => on = false);
      },
    );
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.l.t('no_voice'))));
      return;
    }
    setState(() => on = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.s.l;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: T.navy,
        backgroundColor: T.navySoft,
        visualDensity: VisualDensity.compact,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: _toggle,
      icon: Icon(on ? Icons.stop_circle_outlined : Icons.volume_up_outlined, size: 18),
      label: Text(l.t(on ? 'stop_listening' : 'listen'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < Level.scale.length; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsetsDirectional.only(end: i < Level.scale.length - 1 ? 5 : 0),
                    decoration: BoxDecoration(color: i <= level.rank ? level.color : T.border, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(l.t('level.routine'), style: const TextStyle(fontSize: 12, color: T.muted)),
              const Spacer(),
              Text(l.t('level.critical'), style: const TextStyle(fontSize: 12, color: T.muted)),
            ],
          ),
        ],
      ),
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
        InfoRow(icon: Icons.timelapse, text: l.or('regime.${n['work_rest_id']}', '${n['work_rest']}'), sub: l.t('work_rest')),
      for (final a in jList(n['actions'])) InfoRow(icon: Icons.check_circle_outline, text: l.or('${a['key']}', '${a['action']}')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Section(title: l.t('do_now'), children: rows);
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 14, color: T.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: T.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.t('demo_notice'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: T.muted),
          ),
        ],
      ),
    );
  }
}
