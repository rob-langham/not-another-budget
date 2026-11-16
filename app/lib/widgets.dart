import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'theme.dart';

const tabular = [FontFeature.tabularFigures()];

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(24), this.color, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? C.card, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(14)),
      child: child,
    );
    if (onTap == null) return box;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: box));
  }
}

enum Tone { green, orange, grey, blue }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.grey});
  final String text;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.green => (C.greenBg, C.green),
      Tone.orange => (C.orangeBg, C.orange),
      Tone.blue => (C.blueBg, C.blue),
      Tone.grey => (C.greyBg, C.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.color = C.label, this.size = 13});
  final String text;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: size, color: color, height: 1.4));
}

class Big extends StatelessWidget {
  const Big(this.text, {super.key, this.size = 28, this.color = C.ink});
  final String text;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontFamily: display, fontWeight: FontWeight.w700, fontSize: size, color: color, fontFeatures: tabular));
}

class Num extends StatelessWidget {
  const Num(this.text, {super.key, this.bold = false, this.color, this.size = 14, this.strike = false});
  final String text;
  final bool bold, strike;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontFeatures: tabular, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color, fontSize: size,
          decoration: strike ? TextDecoration.lineThrough : null));
}

/// Title row at the top of every page, with optional actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.kicker, required this.title, this.actions = const []});
  final String kicker, title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: 12,
        spacing: 16,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Label(kicker),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ]),
          if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      );
}

/// Lays children out in a row on wide screens and stacks them on narrow ones.
class Responsive extends StatelessWidget {
  const Responsive({super.key, required this.children, this.flex, this.breakpoint = 860, this.gap = 16});
  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint, gap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: flex?[i] ?? 1, child: children[i]),
          ],
        ]);
      });
}

/// Grid of equal tiles that wraps to fewer columns on small screens.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minWidth = 220});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length);
        final w = (c.maxWidth - 16 * (cols - 1)) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.foot, this.valueColor = C.ink, this.onTap});
  final String label, value;
  final Widget? foot;
  final Color valueColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => CardBox(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(label),
          const SizedBox(height: 6),
          Big(value, color: valueColor),
          if (foot != null) ...[const SizedBox(height: 6), foot!],
        ]),
      );
}

class RowLine extends StatelessWidget {
  const RowLine({super.key, required this.left, required this.right, this.last = false});
  final Widget left, right;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: C.rule))),
        child: Row(children: [Expanded(child: left), const SizedBox(width: 12), right]),
      );
}

class TwoLine extends StatelessWidget {
  const TwoLine(this.title, this.sub, {super.key});
  final String title, sub;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 3),
        Label(sub),
      ]);
}

class Note extends StatelessWidget {
  const Note(this.child, {super.key, this.color = C.orangeSoft});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, height: 1.5, color: C.orangeInk), child: child),
      );
}

/// Loads data and reloads it whenever the API reports a change. Shows loading and error states.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.deps = const []});
  final Future<T> Function(Api api) load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final List<Object?> deps;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f;
  Api? _api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.read<Api>();
    if (_api != api) {
      _api?.changes.removeListener(_reload);
      _api = api..changes.addListener(_reload);
      _f = widget.load(api);
    }
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (!_sameDeps(old.deps, widget.deps)) _reload();
  }

  bool _sameDeps(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reload() {
    if (mounted) setState(() => _f = widget.load(_api!));
  }

  @override
  void dispose() {
    _api?.changes.removeListener(_reload);
    super.dispose();
  }

  T? _last;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasData) _last = snap.data;
          final data = snap.data ?? _last;
          if (snap.hasError && data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _reload, child: const Text('Try again')),
                ]),
              ),
            );
          }
          if (data == null) return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
          return widget.builder(context, data as T, _reload);
        },
      );
}

/// Standard page padding + scroll.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 40, narrow ? 16 : 32, narrow ? 16 : 40, 56),
      children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 24), children[i]]],
    );
  }
}

Future<void> runAction(BuildContext context, Future<void> Function() action, {String? done}) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await action();
    if (done != null) m.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: C.orange));
  }
}

Color hex(String s) => Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));

class CategoryDot extends StatelessWidget {
  const CategoryDot(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)));
}
