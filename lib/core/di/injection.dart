import 'package:get_it/get_it.dart';
import '../services/connectivity_service.dart';
import '../services/local_cache_service.dart';
import '../services/outbox_service.dart';

final GetIt getIt = GetIt.instance;

void configureDependencies() {
  _registerCore();
}

void _registerCore() {
  // Repositories and blocs registered per-feature.
  // Idempotent: GetIt is a process-global singleton, so a second bootstrap()
  // in the same isolate (the integration_test suite runs one per role) would
  // otherwise throw "already registered" and abort the test before it could
  // assert anything. registerSingleton on an already-registered type is a
  // no-op-by-skip here rather than a crash.
  if (!getIt.isRegistered<ConnectivityService>()) {
    getIt.registerSingleton(ConnectivityService.instance);
  }
  if (!getIt.isRegistered<LocalCacheService>()) {
    getIt.registerSingleton(LocalCacheService.instance);
  }
  if (!getIt.isRegistered<OutboxService>()) {
    getIt.registerSingleton(OutboxService.instance);
  }
}
