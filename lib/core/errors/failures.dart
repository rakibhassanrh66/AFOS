abstract class Failure {
  final String message;
  const Failure(this.message);
}
class NetworkFailure    extends Failure { const NetworkFailure([super.message='No internet connection.']); }
class ServerFailure     extends Failure { const ServerFailure([super.message='Server error — try again.']); }
class AuthFailure       extends Failure { const AuthFailure([super.message='Authentication failed.']); }
class SessionExpired    extends Failure { const SessionExpired([super.message='Session expired. Please log in.']); }
class ValidationFailure extends Failure { const ValidationFailure(super.message); }
class TimeoutFailure    extends Failure { const TimeoutFailure([super.message='Request timed out.']); }
class CacheFailure      extends Failure { const CacheFailure([super.message='Could not load cached data.']); }
class UnknownFailure    extends Failure { const UnknownFailure([super.message='Something went wrong.']); }
