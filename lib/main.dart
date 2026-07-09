import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bootstrap.dart';
import 'config/app_config.dart';
import 'config/routes/app_router.dart';
import 'config/theme/dark_theme.dart';
import 'config/theme/light_theme.dart';
import 'features/settings/bloc/theme_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
  runApp(const AFOSApp());
}

class AFOSApp extends StatelessWidget {
  const AFOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ThemeBloc(),
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) => MaterialApp.router(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(accent: state.accentColor),
          darkTheme: buildDarkTheme(accent: state.accentColor),
          themeMode: state.mode,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
