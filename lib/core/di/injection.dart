import 'package:get_it/get_it.dart';
import '../services/connectivity_service.dart';
import '../services/local_cache_service.dart';
import '../services/outbox_service.dart';

final GetIt getIt = GetIt.instance;

void configureDependencies() {
  _registerCore();
}

void _registerCore() {
  // Repositories and blocs registered per-feature
  getIt.registerSingleton(ConnectivityService.instance);
  getIt.registerSingleton(LocalCacheService.instance);
  getIt.registerSingleton(OutboxService.instance);
}
