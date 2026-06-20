import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/network/dio_client.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/i18n/locale_provider.dart';
import 'core/i18n/app_translations.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = TokenStorage();
  final client = DioClient(tokens);
  runApp(AgricoreApp(tokens: tokens, client: client));
}

class AgricoreApp extends StatelessWidget {
  final TokenStorage tokens;
  final DioClient client;
  const AgricoreApp({super.key, required this.tokens, required this.client});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TokenStorage>.value(value: tokens),
        Provider<DioClient>.value(value: client),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(client, tokens),
        ),
        ChangeNotifierProvider<CartModel>(
          create: (_) => CartModel()..load(),
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider()..load(),
        ),
      ],
      child: Builder(
        builder: (context) {
          final auth = context.read<AuthProvider>();
          final router = buildRouter(auth);
          final loc = context.watch<LocaleProvider>();
          return MaterialApp.router(
            title: 'Agricore Dynamics',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            routerConfig: router,
            locale: loc.locale,
            supportedLocales: kLanguages.map((l) => Locale(l.code)),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
