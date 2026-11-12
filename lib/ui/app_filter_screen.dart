import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../services/native_bridge.dart';

/// White-list manager. Only ticked packages can have notifications read or answered; everything else
/// is dropped natively before any content is touched.
class AppFilterScreen extends StatefulWidget {
  const AppFilterScreen({super.key});

  @override
  State<AppFilterScreen> createState() => _AppFilterScreenState();
}

class _AppFilterScreenState extends State<AppFilterScreen> {
  List<AppInfo> _apps = const [];
  Set<String> _allowed = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _allowed = S.settings.whitelist;
    _load();
  }

  Future<void> _load() async {
    final apps = await S.native.getApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  Future<void> _toggle(String pkg, bool on) async {
    final next = Set<String>.of(_allowed);
    on ? next.add(pkg) : next.remove(pkg);
    setState(() => _allowed = next);
    await S.settings.setWhitelist(next);
    await S.native.setWhitelist(next.toList());
  }

  Widget _icon(AppInfo a, AegisPalette pal) {
    final ic = a.icon;
    if (ic != null) {
      return SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            ic,
            width: 44,
            height: 44,
            cacheWidth: 88,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: pal.accent.op(.18),
      child: Text(a.name.isEmpty ? '?' : a.name[0].toUpperCase(),
          style: TextStyle(color: pal.accent, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = AegisPalette.byId(S.settings.themeId);
    final q = _query.toLowerCase();
    final list = _apps
        .where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.pkg.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final sa = _allowed.contains(a.pkg) ? 0 : 1;
        final sb = _allowed.contains(b.pkg) ? 0 : 1;
        return sa != sb ? sa.compareTo(sb) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: const Text('App selection filter')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search apps',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: pal.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'AEGIS ignores every app that is not ticked.',
                style: TextStyle(color: pal.subtext, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: list.length,
                    itemExtent: 64,
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return SwitchListTile(
                        secondary: _icon(a, pal),
                        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(a.pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
                        value: _allowed.contains(a.pkg),
                        onChanged: (v) => _toggle(a.pkg, v),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
