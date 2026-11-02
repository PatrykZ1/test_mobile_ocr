import 'package:flutter/material.dart';
import '../services/mock_auth_service.dart';
import '../widgets/login_header.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscure = true;
  bool _rememberMe = true;
  bool _loading = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _fillDemo() {
    _emailCtrl.text = 'demo@plate.app';
    _passCtrl.text = 'demo1234';
    setState(() => _statusMessage = null);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    final res = await MockAuthService.instance.signIn(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _statusMessage = res.message;
      _statusOk = res.ok;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(res.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: res.ok
              ? Colors.green.shade700
              : Theme.of(context).colorScheme.error,
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LoginHeader(),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType:
                                  TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon:
                                    Icon(Icons.alternate_email),
                              ),
                              validator: (v) {
                                if (v == null ||
                                    v.trim().isEmpty) {
                                  return 'Podaj e-mail';
                                }
                                if (!v.contains('@')) {
                                  return 'E-mail musi zawierać @';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Hasło',
                                prefixIcon: const Icon(
                                    Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() =>
                                      _obscure = !_obscure),
                                  icon: Icon(_obscure
                                      ? Icons.visibility_outlined
                                      : Icons
                                          .visibility_off_outlined),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Podaj hasło';
                                }
                                if (v.length < 4) {
                                  return 'Min. 4 znaki';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (v) => setState(() =>
                                      _rememberMe = v ?? false),
                                ),
                                const Text('Zapamiętaj mnie'),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Reset hasła - mock.'),
                                          behavior: SnackBarBehavior
                                              .floating,
                                        ),
                                      );
                                  },
                                  child: const Text(
                                      'Nie pamiętasz hasła?'),
                                ),
                              ],
                            ),
                            if (_statusMessage != null)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: (_statusOk
                                          ? Colors.green
                                          : Theme.of(context)
                                              .colorScheme
                                              .error)
                                      .withOpacity(0.14),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _statusOk
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                          _statusMessage!),
                                    ),
                                  ],
                                ),
                              ),
                            if (_statusMessage != null)
                              const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed:
                                  _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Zaloguj się'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  _loading ? null : _fillDemo,
                              icon: const Icon(
                                  Icons.bolt_outlined,
                                  size: 18),
                              label: const Text(
                                  'Użyj konta demo'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12),
                        child: Text('lub',
                            style: TextStyle(
                                color: Colors.grey[500])),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Ekran demo - nic nie jest wysylane.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


