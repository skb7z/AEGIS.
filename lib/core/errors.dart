/// Thrown when the device cannot reach the internet (socket / timeout / DNS).
class NetworkFailure implements Exception {
  const NetworkFailure([this.detail = '']);
  final String detail;
  @override
  String toString() => 'NetworkFailure($detail)';
}

/// Thrown for API-level problems that should be spoken to the user.
class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
  @override
  String toString() => 'ApiFailure($message)';
}
