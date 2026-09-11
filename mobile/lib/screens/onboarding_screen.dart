import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// معالج إعداد الصيدلية بأسلوب Upwork (نظير صفحة /onboarding في الويب):
/// سؤال واحد لكل شاشة، شريط تقدم، تخطي الخطوات الاختيارية، مراجعة بأزرار
/// تعديل قافزة، ثم حفظ واحد عبر PUT /pharmacy/onboarding مع complete=true.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // 0 الاسم، 1 التواصل، 2 الموقع، 3 المراجعة، 4 النجاح
  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _addr1 = TextEditingController();
  final _addr2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postal = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _website.dispose();
    _addr1.dispose();
    _addr2.dispose();
    _city.dispose();
    _state.dispose();
    _postal.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      final st = await auth.loadOnboarding();
      final p = st.pharmacy;
      if (!mounted) return;
      setState(() {
        _name.text = p.name;
        _phone.text = p.phone;
        _website.text = p.website;
        _addr1.text = p.addressLine1;
        _addr2.text = p.addressLine2;
        _city.text = p.city;
        _state.text = p.stateProvince;
        _postal.text = p.postalCode;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(context, e);
      });
    }
  }

  OnboardingProfile _profile() => OnboardingProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        website: _website.text.trim(),
        addressLine1: _addr1.text.trim(),
        addressLine2: _addr2.text.trim(),
        city: _city.text.trim(),
        stateProvince: _state.text.trim(),
        postalCode: _postal.text.trim(),
        country: '',
      );

  bool get _nameValid => _name.text.trim().runes.length >= 2;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.completeOnboarding(_profile());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 4;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(context, e);
      });
    }
  }

  void _next() {
    if (_step == 0 && !_nameValid) {
      setState(() => _error = context.tr('ob_name_required'));
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_step == 4) return _success();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_pharmacy_rounded, color: kBrandSeed),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('ob_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.trF('ob_step', <String, String>{'n': '${_step + 1}'}),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_step + 1) / 4,
                  minHeight: 7,
                  backgroundColor: kBrandSeed.withOpacity(0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(kBrandSeed),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _stepBody(_step),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepBody(int step) {
    final fields = <Widget>[];
    if (step == 0) {
      fields.addAll([
        _stepTitle(context.tr('ob_welcome_title')),
        _stepHint(context.tr('ob_welcome_hint')),
        const SizedBox(height: 16),
        TextFormField(
          controller: _name,
          autofocus: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: appInputDecoration(context, context.tr('ob_name'),
              icon: Icons.storefront_rounded),
        ),
      ]);
    } else if (step == 1) {
      fields.addAll([
        _stepTitle(context.tr('ob_contact_title')),
        _stepHint(context.tr('ob_contact_hint')),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: appInputDecoration(context, context.tr('ob_phone'),
              icon: Icons.phone_outlined),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _website,
          keyboardType: TextInputType.url,
          decoration: appInputDecoration(context, context.tr('ob_website'),
              icon: Icons.language_rounded),
        ),
      ]);
    } else if (step == 2) {
      fields.addAll([
        _stepTitle(context.tr('ob_location_title')),
        _stepHint(context.tr('ob_location_hint')),
        const SizedBox(height: 16),
        TextFormField(
          controller: _addr1,
          decoration: appInputDecoration(context, context.tr('ob_address1'),
              icon: Icons.location_on_outlined),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addr2,
          decoration: appInputDecoration(context, context.tr('ob_address2')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _city,
                decoration: appInputDecoration(context, context.tr('ob_city')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _state,
                decoration:
                    appInputDecoration(context, context.tr('ob_state')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _postal,
          keyboardType: TextInputType.number,
          decoration:
              appInputDecoration(context, context.tr('ob_postal')),
        ),
      ]);
    } else {
      fields.add(_review());
    }

    final optional = step == 1 || step == 2;
    return Column(
      key: ValueKey<int>(step),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...fields,
        const SizedBox(height: 22),
        if (_error != null) ...[
          ErrorBox(message: _error!),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            if (step > 0)
              TextButton(
                onPressed: () => setState(() {
                  _error = null;
                  _step -= 1;
                }),
                child: Text(context.tr('back')),
              ),
            const Spacer(),
            if (optional)
              TextButton(
                onPressed: _next,
                child: Text(context.tr('skip')),
              ),
            const SizedBox(width: 4),
            if (step < 3)
              Expanded(
                flex: 2,
                child: PrimaryButton(label: context.tr('next'), onPressed: _next),
              )
            else
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: _saving ? context.tr('ob_saving') : context.tr('save'),
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _review() {
    final rows = <MapEntry<String, String>>[
      MapEntry(context.tr('ob_name'), _name.text.trim()),
      MapEntry(context.tr('ob_phone'), _phone.text.trim()),
      MapEntry(context.tr('ob_website'), _website.text.trim()),
      MapEntry(context.tr('ob_address1'), _addr1.text.trim()),
      MapEntry(context.tr('ob_address2'), _addr2.text.trim()),
      MapEntry(context.tr('ob_city'), _city.text.trim()),
      MapEntry(context.tr('ob_state'), _state.text.trim()),
      MapEntry(context.tr('ob_postal'), _postal.text.trim()),
    ];
    // الخطوة التي يُعدَّل منها كل صف: 0 الاسم، 1 تواصل، 2 موقع
    final jump = <int>[0, 1, 1, 2, 2, 2, 2, 2];
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              context.tr('ob_review_title'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            for (var i = 0; i < rows.length; i++)
              if (rows[i].value.isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(rows[i].value,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(rows[i].key, style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      _error = null;
                      _step = jump[i];
                    }),
                    child: Text(context.tr('ob_review_edit')),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _success() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF10B981), size: 62),
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('ob_complete_title'),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('ob_complete_sub'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 240,
              child: PrimaryButton(
                label: context.tr('ob_enter'),
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepTitle(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _stepHint(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
}
