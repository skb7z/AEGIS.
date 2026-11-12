import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_services.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

/// Name, age, gender, country. Shown once after the first Google sign-in, and later from the
/// profile icon in Settings.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _country;
  late String _gender;
  String? _error;
  bool _saving = false;

  String _t(String bn, String en) => S.settings.language == 'bn' ? bn : en;

  @override
  void initState() {
    super.initState();
    final p = S.auth.profile;
    _name = TextEditingController(text: p.name.isNotEmpty ? p.name : (S.auth.user?.name ?? ''));
    _age = TextEditingController(text: p.age?.toString() ?? '');
    _country = TextEditingController(text: p.country);
    _gender = p.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim());
    final country = _country.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _t('নাম লিখুন।', 'Please enter your name.'));
      return;
    }
    if (age == null || age < 5 || age > 120) {
      setState(() => _error = _t('সঠিক বয়স লিখুন।', 'Please enter a valid age.'));
      return;
    }
    if (_gender.isEmpty) {
      setState(() => _error = _t('জেন্ডার বেছে নিন।', 'Please choose your gender.'));
      return;
    }
    if (country.isEmpty) {
      setState(() => _error = _t('দেশের নাম লিখুন।', 'Please enter your country.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await S.auth.saveProfile(AegisProfile(name: name, age: age, gender: _gender, country: country));
    if (!mounted) return;
    setState(() => _saving = false);
    // On first run the auth gate switches to Home by itself.
    if (!widget.firstRun) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pal = AegisPalette.byId(S.settings.themeId);
    return PopScope(
      canPop: !widget.firstRun,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.firstRun,
          title: Text(widget.firstRun
              ? _t('আপনার পরিচয়', 'About you')
              : _t('প্রোফাইল', 'Profile')),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              if (widget.firstRun)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    _t('Aegis আপনাকে ঠিকমতো চিনতে এই কয়েকটা তথ্য দিন। পরে সেটিংস থেকে বদলাতে পারবেন।',
                        'Tell Aegis a little about you. You can change this later in Settings.'),
                    style: TextStyle(color: pal.subtext, height: 1.4),
                  ),
                ),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _t('নাম', 'Name'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _age,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: InputDecoration(
                  labelText: _t('বয়স', 'Age'),
                  prefixIcon: const Icon(Icons.cake_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Text(_t('জেন্ডার', 'Gender'), style: TextStyle(color: pal.subtext, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: 'male', label: Text(_t('ছেলে', 'Male')), icon: const Icon(Icons.male_rounded)),
                  ButtonSegment(
                      value: 'female',
                      label: Text(_t('মেয়ে', 'Female')),
                      icon: const Icon(Icons.female_rounded)),
                ],
                selected: _gender.isEmpty ? <String>{} : {_gender},
                onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? '' : s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _country,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _t('দেশ', 'Country'),
                  prefixIcon: const Icon(Icons.public_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_t('সেভ করুন', 'Save')),
                ),
              ),
              if (widget.firstRun)
                TextButton(
                  onPressed: S.auth.signOut,
                  child: Text(_t('অন্য অ্যাকাউন্টে সাইন ইন', 'Use a different account'),
                      style: TextStyle(color: pal.subtext)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
