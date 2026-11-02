class MockAuthResult {
  const MockAuthResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

class MockAuthService {
  MockAuthService._();
  static final instance = MockAuthService._();

  Future<MockAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!email.contains('@')) {
      return const MockAuthResult(
        ok: false,
        message: 'Podaj poprawny adres e-mail.',
      );
    }
    if (password.length < 4) {
      return const MockAuthResult(
        ok: false,
        message: 'Hasło musi mieć min. 4 znaki (mock).',
      );
    }
    return MockAuthResult(
      ok: true,
      message: 'Zalogowano jako $email (mock)',
    );
  }
}
