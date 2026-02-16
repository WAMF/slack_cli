import 'dart:convert';

import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('Slack', () {
    late http.Client httpClient;
    late Slack slack;

    setUp(() {
      httpClient = _MockHttpClient();
      slack = Slack(token: 'xoxp-test', httpClient: httpClient);
    });

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    group('postMessage', () {
      test('returns a typed SlackMessage', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': 'C123',
              'ts': '111.222',
              'message': {'text': 'Hi', 'ts': '111.222'},
            }),
            200,
          ),
        );

        final msg = await slack.postMessage(
          channel: 'C123',
          text: 'Hi',
        );

        expect(msg.channel, equals('C123'));
        expect(msg.ts, equals('111.222'));
        expect(msg.text, equals('Hi'));
      });
    });

    group('listChannels', () {
      test('returns typed SlackChannel list', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channels': [
                {'id': 'C1', 'name': 'general', 'is_private': false},
                {'id': 'G2', 'name': 'secret', 'is_private': true},
              ],
            }),
            200,
          ),
        );

        final channels = await slack.listChannels();

        expect(channels, hasLength(2));
        expect(channels[0].id, equals('C1'));
        expect(channels[0].name, equals('general'));
        expect(channels[0].isPrivate, isFalse);
        expect(channels[1].id, equals('G2'));
        expect(channels[1].isPrivate, isTrue);
      });
    });

    group('joinChannel', () {
      test('delegates to the underlying client', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true}),
            200,
          ),
        );

        await slack.joinChannel('C123');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured;

        expect(captured[0] as Uri, equals(SlackUrls.conversationsJoin));
      });
    });

    test('close delegates to the underlying client', () {
      when(() => httpClient.close()).thenReturn(null);
      slack.close();
      verify(() => httpClient.close()).called(1);
    });
  });
}
