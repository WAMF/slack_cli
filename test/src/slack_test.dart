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

      test('aggregates paginated channel responses', () async {
        var callCount = 0;
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async {
            callCount++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'channels': [
                  if (callCount == 1)
                    {'id': 'C1', 'name': 'general', 'is_private': false}
                  else
                    {'id': 'G2', 'name': 'secret', 'is_private': true},
                ],
                'response_metadata': {
                  'next_cursor': callCount == 1 ? 'cursor-1' : '',
                },
              }),
              200,
            );
          },
        );

        final channels = await slack.listChannels();

        expect(channels, hasLength(2));
        expect(channels[0].id, equals('C1'));
        expect(channels[1].id, equals('G2'));
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

    group('updateMessage', () {
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
              'channel': 'C1',
              'ts': '1.0',
              'message': {'text': 'updated'},
            }),
            200,
          ),
        );

        final msg = await slack.updateMessage(
          channel: 'C1',
          ts: '1.0',
          text: 'updated',
        );

        expect(msg.channel, equals('C1'));
        expect(msg.text, equals('updated'));
      });
    });

    group('deleteMessage', () {
      test('completes without error', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'channel': 'C1', 'ts': '1.0'}),
            200,
          ),
        );

        await slack.deleteMessage(channel: 'C1', ts: '1.0');

        verify(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).called(1);
      });
    });

    group('conversationsHistory', () {
      test('returns CursorPage of SlackMessage', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '2.0', 'text': 'second', 'user': 'U1'},
                {'ts': '1.0', 'text': 'first', 'user': 'U2'},
              ],
              'has_more': true,
              'response_metadata': {'next_cursor': 'abc123'},
            }),
            200,
          ),
        );

        final page = await slack.conversationsHistory(channel: 'C1');

        expect(page.items, hasLength(2));
        expect(page.items[0].text, equals('second'));
        expect(page.items[0].user, equals('U1'));
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, equals('abc123'));
      });

      test('treats empty cursor as null', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': <Map<String, dynamic>>[],
              'has_more': false,
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          ),
        );

        final page = await slack.conversationsHistory(channel: 'C1');

        expect(page.nextCursor, isNull);
      });
    });

    group('conversationsReplies', () {
      test('returns CursorPage of SlackMessage', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'parent', 'user': 'U1'},
                {'ts': '1.1', 'text': 'reply', 'user': 'U2'},
              ],
              'has_more': false,
            }),
            200,
          ),
        );

        final page = await slack.conversationsReplies(
          channel: 'C1',
          ts: '1.0',
        );

        expect(page.items, hasLength(2));
        expect(page.items[1].text, equals('reply'));
        expect(page.hasMore, isFalse);
      });
    });

    group('conversationsInfo', () {
      test('returns a typed SlackChannel', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': {
                'id': 'C1',
                'name': 'general',
                'is_private': false,
                'topic': {'value': 'Announcements'},
                'purpose': {'value': 'General chat'},
                'num_members': 42,
                'is_archived': false,
              },
            }),
            200,
          ),
        );

        final channel = await slack.conversationsInfo(channel: 'C1');

        expect(channel.id, equals('C1'));
        expect(channel.name, equals('general'));
        expect(channel.topic, equals('Announcements'));
        expect(channel.purpose, equals('General chat'));
        expect(channel.memberCount, equals(42));
      });
    });

    group('conversationsMembers', () {
      test('returns CursorPage of String', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'members': ['U1', 'U2', 'U3'],
              'response_metadata': {'next_cursor': 'xyz'},
            }),
            200,
          ),
        );

        final page = await slack.conversationsMembers(channel: 'C1');

        expect(page.items, equals(['U1', 'U2', 'U3']));
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, equals('xyz'));
      });
    });

    group('usersList', () {
      test('returns CursorPage of SlackUser', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'members': [
                {
                  'id': 'U1',
                  'name': 'jane',
                  'real_name': 'Jane Doe',
                  'is_bot': false,
                  'deleted': false,
                  'profile': {'display_name': 'Jane'},
                },
              ],
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          ),
        );

        final page = await slack.usersList();

        expect(page.items, hasLength(1));
        expect(page.items[0].id, equals('U1'));
        expect(page.items[0].realName, equals('Jane Doe'));
        expect(page.hasMore, isFalse);
      });
    });

    group('usersInfo', () {
      test('returns a typed SlackUser', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'user': {
                'id': 'U1',
                'name': 'jane',
                'real_name': 'Jane Doe',
                'is_bot': false,
                'deleted': false,
                'profile': {
                  'display_name': 'Jane',
                  'email': 'jane@example.com',
                },
              },
            }),
            200,
          ),
        );

        final user = await slack.usersInfo(user: 'U1');

        expect(user.id, equals('U1'));
        expect(user.realName, equals('Jane Doe'));
        expect(user.email, equals('jane@example.com'));
      });
    });

    test('close delegates to the underlying client', () {
      when(() => httpClient.close()).thenReturn(null);
      slack.close();
      verify(() => httpClient.close()).called(1);
    });
  });
}
