import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/notify.dart';
import '../core/theme.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = s.l;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text(t, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: T.muted)),
        );

    Widget row(String title, String value, VoidCallback onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          subtitle: Text(value, style: const TextStyle(color: T.muted)),
          trailing: TextButton(onPressed: onTap, child: Text(l.t('change'))),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Narrow(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label(l.t('language')),
            for (final e in L10n.supported.entries)
              ChoiceTile(title: e.value, selected: s.lang == e.key, onTap: () => s.setLang(e.key)),
            if (l.isDraft) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(l.t('draft'), style: const TextStyle(fontSize: 13, color: T.warn))),
            const SizedBox(height: 8),
            Section(children: [
              row(l.t('crew'), '${s.crewName} · ${s.siteName}', () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await s.resetCrew();
              }),
              const Divider(),
              row(l.t('badge'), s.badge ?? l.t('no_badge_short'), () => BadgePicker.show(context)),
            ]),
            Section(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.alertsOn,
                onChanged: (v) async {
                  final ok = await s.setAlerts(v);
                  if (v && !ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('notifications_blocked'))));
                  }
                },
                title: Text(l.t('notifications'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                subtitle: Text(l.t('notifications_body'), style: const TextStyle(color: T.muted)),
              ),
              if (DeviceNotify.blocked) Text(l.t('notifications_blocked'), style: const TextStyle(fontSize: 13, color: T.warn)),
            ]),
            if (ApiConfig.serverEditable)
              Section(children: [
                row(l.t('server'), s.api.baseUrl.replaceAll(RegExp(r'/api$'), ''), () => ServerDialog.show(context)),
              ]),
            label(l.t('about')),
            Section(children: [
              Text(l.t('about_body'), style: const TextStyle(fontSize: 14, color: T.text, height: 1.5)),
              const SizedBox(height: 10),
              Text(l.t('privacy'), style: const TextStyle(fontSize: 13.5, color: T.muted, height: 1.45)),
              const SizedBox(height: 10),
              const Text('HeatGuard Worker 1.0.0', style: TextStyle(fontSize: 12.5, color: T.muted)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Choose or remove the wearable badge linked to this device.
class BadgePicker {
  static Future<void> show(BuildContext context) async {
    final s = AppScope.of(context);
    await s.loadBadges();
    if (!context.mounted) return;
    final l = s.l;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Directionality(
        textDirection: l.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Narrow(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
            Text(l.t('badge_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l.t('badge_body'), style: const TextStyle(fontSize: 14.5, color: T.muted, height: 1.45)),
            const SizedBox(height: 18),
            ChoiceTile(
              title: l.t('no_badge'),
              selected: s.workerId == null,
              onTap: () {
                Navigator.pop(ctx);
                s.setBadge(null);
              },
            ),
            for (final b in s.badges)
              ChoiceTile(
                title: '${b['badge']}',
                selected: s.workerId == b['worker_id'],
                leading: const Icon(Icons.watch_outlined, color: T.navy),
                onTap: () {
                  Navigator.pop(ctx);
                  s.setBadge(b['worker_id'] as String);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

/// Server address for the native apps (a phone must be told where the HeatGuard server is).
class ServerDialog {
  static Future<void> show(BuildContext context) async {
    final s = AppScope.of(context);
    final l = s.l;
    final ctrl = TextEditingController(text: s.serverUrl?.replaceAll(RegExp(r'/api$'), '') ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('server')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: InputDecoration(hintText: l.t('server_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('back'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(l.t('save')),
          ),
        ],
      ),
    );
    if (v != null) await s.setServer(v);
  }
}
