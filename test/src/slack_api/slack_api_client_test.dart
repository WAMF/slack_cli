import 'dart:convert';

import 'package:dart_slack/src/slack_api/slack_api_client.dart';
import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('SlackApiClient', () {
    const token = 'xoxp-test-token';
    late http.Client httpClient;
    late SlackApiClient slackClient;

    setUp(() {
      httpClient = _MockHttpClient();
      slackClient = SlackApiClient(
        token: token,
        httpClient: httpClient,
      );
    });

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    group('postMessage', () {
      test('sends correct headers and body', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'ts': '1234.5678'}),
            200,
          ),
        );

        await slackClient.postMessage(
          channel: 'C123',
          text: 'Hello',
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: captureAny(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final headers = captured[1] as Map<String, String>;
        final body =
            jsonDecode(captured[2] as String) as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.postMessage));
        expect(headers['Authorization'], equals('Bearer $token'));
        expect(
          headers['Content-Type'],
          equals('application/json; charset=utf-8'),
        );
        expect(body['channel'], equals('C123'));
        expect(body['text'], equals('Hello'));
        expect(body.containsKey('thread_ts'), isFalse);
      });

      test('includes thread_ts when provided', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'ts': '1234.5678'}),
            200,
          ),
        );

        await slackClient.postMessage(
          channel: 'C123',
          text: 'Reply',
          threadTs: '1111.2222',
        );

        final captured = verify(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final body =
            jsonDecode(captured[0] as String) as Map<String, dynamic>;
        expect(body['thread_ts'], equals('1111.2222'));
      });

      test('throws SlackApiException when API returns ok: false',
          () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': 'channel_not_found',
            }),
            200,
          ),
        );

        expect(
          () => slackClient.postMessage(
            channel: 'C_BAD',
            text: 'Hello',
          ),
          throwsA(
            isA<SlackApiException>().having(
              (e) => e.error,
              'error',
              'channel_not_found',
            ),
          ),
        );
      });

      test(
        'throws SlackApiException with unknown_error '
        'when error field is missing',
        () async {
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => http.Response(
              jsonEncode({'ok': false}),
              200,
            ),
          );

          expect(
            () => slackClient.postMessage(
              channel: 'C123',
              text: 'Hello',
            ),
            throwsA(
              isA<SlackApiException>().having(
                (e) => e.error,
                'error',
                'unknown_error',
              ),
            ),
          );
        },
      );
    });

    test('close delegates to httpClient', () {
      when(() => httpClient.close()).thenReturn(null);
      slackClient.close();
      verify(() => httpClient.close()).called(1);
    });

    group('rate limiting', () {
      late SlackApiClient retryClient;

      setUp(() {
        retryClient = SlackApiClient(
          token: token,
          httpClient: httpClient,
          delay: (_) async {},
        );
      });

      test('retries GET on 429 and succeeds', () async {
        var callCount = 0;
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode({'ok': false, 'error': 'ratelimited'}),
              429,
              headers: {'retry-after': '1'},
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'channel': {
                'id': 'C1',
                'name': 'general',
                'is_private': false,
              },
            }),
            200,
          );
        });

        final result =
            await retryClient.conversationsInfo(channel: 'C1');

        expect(result['channel'], isNotNull);
        expect(callCount, equals(2));
      });

      test('retries POST on 429 and succeeds', () async {
        var callCount = 0;
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode({'ok': false, 'error': 'ratelimited'}),
              429,
              headers: {'retry-after': '2'},
            );
          }
          return http.Response(
            jsonEncode({'ok': true, 'ts': '1234.5678'}),
            200,
          );
        });

        await retryClient.postMessage(channel: 'C1', text: 'hi');

        expect(callCount, equals(2));
      });

      test('throws after max retry attempts', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'ratelimited'}),
            429,
            headers: {'retry-after': '1'},
          ),
        );

        expect(
          () => retryClient.conversationsInfo(channel: 'C1'),
          throwsA(
            isA<SlackApiException>().having(
              (e) => e.error,
              'error',
              'ratelimited',
            ),
          ),
        );
      });

      test('does not retry non-429 errors', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'invalid_auth'}),
            401,
          ),
        );

        expect(
          () => retryClient.conversationsInfo(channel: 'C1'),
          throwsA(
            isA<SlackApiException>().having(
              (e) => e.error,
              'error',
              'invalid_auth',
            ),
          ),
        );

        verify(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).called(1);
      });
    });
  });
}
