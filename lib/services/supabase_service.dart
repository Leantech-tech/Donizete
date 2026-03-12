import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static const String _supabaseUrl = 'https://bbmifkqxxdlhmddvydpz.supabase.co';
  static const String _supabaseAnonKey = 'sb_publishable_k4s70VwrU8ZM2RrmzuFFmQ_GNGYTyRZ';

  static SupabaseClient? _client;

  static Future<void> initialize() async {
    try {
      // Tenta carregar o .env, mas continua se falhar (comum no ambiente web/produção)
      try {
        await dotenv.load(fileName: '.env');
      } catch (e) {
        debugPrint('Aviso: Não foi possível carregar o arquivo .env: $e');
      }
      
      final url = dotenv.env['SUPABASE_URL'] ?? _supabaseUrl;
      final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? _supabaseAnonKey;

      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
      );
      
      _client = Supabase.instance.client;
      debugPrint('Supabase inicializado com sucesso.');
    } catch (e) {
      debugPrint('Erro crítico ao inicializar Supabase: $e');
    }
  }

  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase não foi inicializado. Chame SupabaseService.initialize() primeiro.');
    }
    return _client!;
  }

  static Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signUpWithEmail(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }
}
