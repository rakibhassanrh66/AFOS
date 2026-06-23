class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override String toString() => 'AppException: $message';
}
class NetworkException  extends AppException { const NetworkException([super.message='Network error']); }
class ServerException   extends AppException {
  final int? statusCode;
  const ServerException([super.message='Server error', this.statusCode]);
}
class AuthException     extends AppException { const AuthException([super.message='Auth error']); }
class TimeoutException  extends AppException { const TimeoutException([super.message='Timed out']); }
class CacheException    extends AppException { const CacheException([super.message='Cache error']); }
