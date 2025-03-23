class AppConfig {
  static const String baseUrl = 'http://localhost:8080';
  static const String apiVersion = 'v1';
  
  static String get authBaseUrl => '$baseUrl/api/$apiVersion/auth';
  static String get openaiBaseUrl => '$baseUrl/api/$apiVersion/openai';
  static String get apiVersionBaseUrl => '$baseUrl/api/$apiVersion';
  
}
