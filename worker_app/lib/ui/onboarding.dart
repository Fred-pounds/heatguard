import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../l10n/strings.dart';
import 'settings.dart';
import 'widgets.dart';

/// First run: language, crew, optional badge. The choices are remembered on the device.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  J? crew;
  List<J> badges = [];
  String? workerId;
  bool loadingBadges = false;

  Future<void> _toBadges() async {
    final s = AppScope.of(context);
    setState(() {
      step = 2;
      loadingBadges = true;
      workerId = null;
    });
    try {
      badges = jList(await s.api.get('/worker/badges/${crew!['crew_id']}'));
    } catch (_) {
      badges = [];
    }
    if (mounted) setState(() => loadingBadges = false);
  }

  Future<void> _finish() async {
    final s = AppScope.of(context);
    s.badges = badges;
    await s.setCrew(crew!);
    if (workerId != null) await s.setBadge(workerId);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    return Scaffold(
      body: SafeArea(
        child: Narrow(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(children: [
                if (step > 0)
                  IconButton(
                    tooltip: l.t('back'),
                    onPressed: () => setState(() => step--),
                    icon: Icon(l.isRtl ? Icons.arrow_forward : Icons.arrow_back),
                  )
                else
                  const AppLogo(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(fill(l.t('step_of'), {'n': step + 1}), style: const TextStyle(color: T.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                if (step > 0 && ApiConfig.serverEditable)
                  IconButton(tooltip: l.t('server'), icon: const Icon(Icons.dns_outlined), onPressed: () => ServerDialog.show(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsetsDirectional.only(end: i < 2 ? 6 : 0),
                      decoration: BoxDecoration(color: i <= step ? T.navy : T.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
            Expanded(child: [_language, _crew, _badge][step](context)),
          ]),
        ),
      ),
    );
  }

  Widget _frame({required String title, String? body, required List<Widget> children, required Widget footer}) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 12), children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: T.text, height: 1.25)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(fontSize: 15.5, color: T.muted, height: 1.45)),
            ],
            const SizedBox(height: 24),
            ...children,
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: footer),
      ]);

  Widget _language(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    return _frame(
      title: l.t('app_name'),
      body: l.t('tagline'),
      children: [
        Text(l.t('choose_language'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.muted)),
        const SizedBox(height: 12),
        for (final e in L10n.supported.entries)
          ChoiceTile(
            title: e.value,
            selected: s.lang == e.key,
            onTap: () => s.setLang(e.key),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: T.subtle,
              child: Text(e.key.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: T.text)),
            ),
          ),
        if (l.isDraft) Text(l.t('draft'), style: const TextStyle(fontSize: 13, color: T.warn)),
      ],
      footer: FilledButton(onPressed: () => setState(() => step = 1), child: Text(l.t('continue'))),
    );
  }

  Widget _crew(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;
    final sites = <String, List<J>>{};
    for (final c in s.crews) {
      sites.putIfAbsent('${c['worksite_name']}', () => []).add(c);
    }
    return _frame(
      title: l.t('crew_title'),
      body: l.t('crew_body'),
      children: [
        if (s.crews.isEmpty && s.loadingCrews)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (s.crews.isEmpty)
          Notice(
            icon: Icons.cloud_off_outlined,
            text: l.t('cant_connect'),
            action: TextButton(onPressed: s.loadCatalog, child: Text(l.t('retry'))),
          ),
        for (final site in sites.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, size: 16, color: T.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(site.key, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.muted))),
            ]),
          ),
          for (final c in site.value)
            ChoiceTile(
              title: '${c['name']}',
              selected: crew?['crew_id'] == c['crew_id'],
              onTap: () => setState(() => crew = c),
            ),
          const SizedBox(height: 8),
        ],
      ],
      footer: FilledButton(onPressed: crew == null ? null : _toBadges, child: Text(l.t('continue'))),
    );
  }

  Widget _badge(BuildContext context) {
    final l = AppScope.of(context).l;
    return _frame(
      title: l.t('badge_title'),
      body: l.t('badge_body'),
      children: [
        if (loadingBadges)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          ChoiceTile(
            title: l.t('no_badge'),
            selected: workerId == null,
            onTap: () => setState(() => workerId = null),
            leading: const Icon(Icons.do_not_disturb_alt_outlined, color: T.muted),
          ),
          for (final b in badges)
            ChoiceTile(
              title: '${b['badge']}',
              selected: workerId == b['worker_id'],
              onTap: () => setState(() => workerId = b['worker_id'] as String),
              leading: const Icon(Icons.watch_outlined, color: T.navy),
            ),
        ],
      ],
      footer: FilledButton(onPressed: loadingBadges ? null : _finish, child: Text(l.t('continue'))),
    );
  }
}
