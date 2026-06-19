import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/network/dio_client.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
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
      ],
      child: Builder(
        builder: (context) {
          final auth = context.read<AuthProvider>();
          final router = buildRouter(auth);
          return MaterialApp.router(
            title: 'Agricore Dynamics',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            routerConfig: router,
          );
        },
      ),
    );
  }
}
