import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/config/app_config.dart';
import 'package:evenbill/core/constants/api_constants.dart';

void main() {
  test('AppConfig resolves default API base URL for local testing', () {
    final url = AppConfig.apiBaseUrl;
    expect(url, isNotEmpty);
    expect(url.startsWith('http://'), isTrue);
    expect(url.endsWith('/api/v1'), isTrue);
    expect(ApiConstants.baseUrl, url);
  });
}

