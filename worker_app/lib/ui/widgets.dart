import 'package:material_ui/material_ui.dart';

import '../core/state.dart';
import '../core/theme.dart';

/// Gives every screen access to the single [WorkerState].
class AppScope extends InheritedNotifier<WorkerState> {
  const AppScope({super.key, required WorkerState state, required super.child}) : super(notifier: state);
  static WorkerState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

String hhmm(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '--:--';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String fill(String template, Map<String, Object?> values) =>
    values.entries.fold(template, (s, e) => s.replaceAll('{${e.key}}', '${e.value}'));

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: T.navy, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(Icons.shield_outlined, color: Colors.white, size: size * 0.56),
      );
}

/// White rounded surface with an optional heading.
class Section extends StatelessWidget {
  const Section({super.key, this.title, this.icon, this.trailing, required this.children, this.padding = const EdgeInsets.all(18)});
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: padding,
        decoration: BoxDecoration(color: T.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: T.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: T.text), const SizedBox(width: 10)],
              Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: T.text))),
              ?trailing,
            ]),
            const SizedBox(height: 12),
          ],
          ...children,
        ]),
      );
}

/// One instruction line: an icon in a soft square, then the text.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text, this.sub, this.color = T.navy, this.tint = T.navySoft});
  final IconData icon;
  final String text;
  final String? sub;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: T.text, height: 1.4)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: const TextStyle(fontSize: 13, color: T.muted, height: 1.35)),
                ],
              ]),
            ),
          ),
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = T.muted, this.tint = T.subtle, this.dot = true});
  final String text;
  final Color color;
  final Color tint;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

/// Quiet notice used for "offline" and similar states (tinted, no stripes).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.text, this.color = T.warn, this.tint = const Color(0xFFFEF6EE), this.action});
  final IconData icon;
  final String text;
  final Color color;
  final Color tint;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600, height: 1.4))),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ]),
      );
}

/// Large selectable row used in onboarding and settings.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.title, this.subtitle, required this.selected, required this.onTap, this.leading});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? T.navySoft : T.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? T.navy : T.border, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: T.text)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 13, color: T.muted)),
                  ]),
                ),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? T.navy : T.border),
              ]),
            ),
          ),
        ),
      );
}

/// Centres content and limits its width so the app reads well on phones, tablets and desktop browsers.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.maxWidth = 560});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}
