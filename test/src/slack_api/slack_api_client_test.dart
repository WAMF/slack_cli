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
      registerFallbackValue(
        http.Request('GET', Uri.parse('https://example.com')),
      );
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
        final body = jsonDecode(captured[2] as String) as Map<String, dynamic>;

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

        final body = jsonDecode(captured[0] as String) as Map<String, dynamic>;
        expect(body['thread_ts'], equals('1111.2222'));
      });

      test('throws SlackApiException when API returns ok: false', () async {
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

      test('preserves needed scope metadata on missing_scope errors', () async {
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
              'error': 'missing_scope',
              'needed': 'chat:write',
            }),
            200,
          ),
        );

        expect(
          () => slackClient.postMessage(
            channel: 'C123',
            text: 'Hello',
          ),
          throwsA(
            isA<SlackApiException>()
                .having((e) => e.error, 'error', 'missing_scope')
                .having((e) => e.needed, 'needed', 'chat:write'),
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

    group('listChannels', () {
      test('sends GET with correct query params', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channels': [
                {'id': 'C1', 'name': 'general', 'is_private': false},
              ],
            }),
            200,
          ),
        );

        final result = await slackClient.listChannels();

        expect(result, hasLength(1));
        expect(result[0]['id'], equals('C1'));

        final uri =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.first
                as Uri;

        expect(uri.queryParameters['exclude_archived'], equals('true'));
        expect(
          uri.queryParameters['types'],
          equals('public_channel,private_channel'),
        );
      });

      test('fetches all pages until cursor is exhausted', () async {
        var callCount = 0;
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
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

        final result = await slackClient.listChannels();

        expect(result, hasLength(2));
        expect(result[0]['id'], equals('C1'));
        expect(result[1]['id'], equals('G2'));

        final calls = verify(
          () => httpClient.get(
            captureAny(),
            headers: any(named: 'headers'),
          ),
        ).captured.cast<Uri>();

        expect(calls, hasLength(2));
        expect(calls[0].queryParameters.containsKey('cursor'), isFalse);
        expect(calls[1].queryParameters['cursor'], equals('cursor-1'));
      });
    });

    group('conversationsHistory', () {
      test('sends GET with channel and limit', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'hi', 'user': 'U1'},
              ],
              'has_more': false,
            }),
            200,
          ),
        );

        final result = await slackClient.conversationsHistory(
          channel: 'C1',
          limit: 20,
        );

        expect(result['messages'], hasLength(1));

        final uri =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.first
                as Uri;

        expect(uri.queryParameters['channel'], equals('C1'));
        expect(uri.queryParameters['limit'], equals('20'));
      });
    });

    group('conversationsReplies', () {
      test('sends GET with channel and ts', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'parent', 'user': 'U1'},
              ],
              'has_more': false,
            }),
            200,
          ),
        );

        await slackClient.conversationsReplies(channel: 'C1', ts: '1.0');

        final uri =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.first
                as Uri;

        expect(uri.queryParameters['channel'], equals('C1'));
        expect(uri.queryParameters['ts'], equals('1.0'));
      });
    });

    group('conversationsInfo', () {
      test('sends GET with channel', () async {
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
              },
            }),
            200,
          ),
        );

        final result = await slackClient.conversationsInfo(channel: 'C1');

        expect(result['channel'], isNotNull);
      });

      test('throws on error', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'channel_not_found'}),
            200,
          ),
        );

        expect(
          () => slackClient.conversationsInfo(channel: 'C_BAD'),
          throwsA(
            isA<SlackApiException>().having(
              (e) => e.error,
              'error',
              'channel_not_found',
            ),
          ),
        );
      });
    });

    group('conversationsMembers', () {
      test('returns member IDs', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'members': ['U1', 'U2'],
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          ),
        );

        final result = await slackClient.conversationsMembers(channel: 'C1');

        expect(result['members'], equals(['U1', 'U2']));
      });
    });

    group('conversationsOpen', () {
      test('sends POST to conversations.open with the user', () async {
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
              'channel': {'id': 'D1'},
            }),
            200,
          ),
        );

        final result = await slackClient.conversationsOpen(user: 'U9');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.conversationsOpen));
        expect(body['users'], equals('U9'));
        expect(
          (result['channel'] as Map<String, dynamic>)['id'],
          equals('D1'),
        );
      });
    });

    group('usersList', () {
      test('returns user objects', () async {
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
                  'real_name': 'Jane',
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

        final result = await slackClient.usersList();

        expect(result['members'], hasLength(1));
      });
    });

    group('usersInfo', () {
      test('returns user object', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'user': {
                'id': 'U1',
                'name': 'jane',
                'real_name': 'Jane',
                'is_bot': false,
                'deleted': false,
                'profile': {'display_name': 'Jane'},
              },
            }),
            200,
          ),
        );

        final result = await slackClient.usersInfo(user: 'U1');

        expect(result['user'], isNotNull);
      });
    });

    group('updateMessage', () {
      test('sends POST to chat.update', () async {
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

        await slackClient.updateMessage(
          channel: 'C1',
          ts: '1.0',
          text: 'updated',
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.chatUpdate));
        expect(body['channel'], equals('C1'));
        expect(body['ts'], equals('1.0'));
        expect(body['text'], equals('updated'));
      });
    });

    group('usersProfileSet', () {
      test('sends POST to users.profile.set with profile payload', () async {
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
              'profile': {'status_text': 'On a task'},
            }),
            200,
          ),
        );

        await slackClient.usersProfileSet(
          statusText: 'On a task',
          statusEmoji: ':gear:',
          statusExpiration: 1750000000,
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
        final profile = body['profile'] as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.usersProfileSet));
        expect(profile['status_text'], equals('On a task'));
        expect(profile['status_emoji'], equals(':gear:'));
        expect(profile['status_expiration'], equals(1750000000));
      });

      test('defaults status_expiration to 0', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slackClient.usersProfileSet(statusText: '', statusEmoji: '');

        final body =
            jsonDecode(
                  verify(
                        () => httpClient.post(
                          any(),
                          headers: any(named: 'headers'),
                          body: captureAny(named: 'body'),
                        ),
                      ).captured.first
                      as String,
                )
                as Map<String, dynamic>;
        final profile = body['profile'] as Map<String, dynamic>;

        expect(profile['status_text'], isEmpty);
        expect(profile['status_emoji'], isEmpty);
        expect(profile['status_expiration'], equals(0));
      });

      test('throws SlackApiException on error', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': false, 'error': 'not_allowed_token_type'}),
            200,
          ),
        );

        expect(
          () => slackClient.usersProfileSet(
            statusText: 'On a task',
            statusEmoji: '',
          ),
          throwsA(
            isA<SlackApiException>().having(
              (e) => e.error,
              'error',
              'not_allowed_token_type',
            ),
          ),
        );
      });
    });

    group('deleteMessage', () {
      test('sends POST to chat.delete', () async {
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

        await slackClient.deleteMessage(channel: 'C1', ts: '1.0');

        final uri =
            verify(
                  () => httpClient.post(
                    captureAny(),
                    headers: any(named: 'headers'),
                    body: any(named: 'body'),
                  ),
                ).captured.first
                as Uri;

        expect(uri, equals(SlackUrls.chatDelete));
      });
    });

    group('joinChannel', () {
      test('sends POST to conversations.join', () async {
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

        await slackClient.joinChannel('C1');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.conversationsJoin));
        expect(body['channel'], equals('C1'));
      });
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

        final result = await retryClient.conversationsInfo(channel: 'C1');

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

    group('createCanvas', () {
      test('sends POST to canvases.create with markdown content', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'canvas_id': 'F1'}),
            200,
          ),
        );

        await slackClient.createCanvas(content: '# Title', title: 'Doc');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
        final content = body['document_content'] as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.canvasesCreate));
        expect(body['title'], equals('Doc'));
        expect(body.containsKey('channel_id'), isFalse);
        expect(content['type'], equals('markdown'));
        expect(content['markdown'], equals('# Title'));
      });

      test('includes channel_id when a channel is given', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'canvas_id': 'F2'}),
            200,
          ),
        );

        await slackClient.createCanvas(content: 'body', channel: 'C9');

        final body =
            jsonDecode(
                  verify(
                        () => httpClient.post(
                          any(),
                          headers: any(named: 'headers'),
                          body: captureAny(named: 'body'),
                        ),
                      ).captured.first
                      as String,
                )
                as Map<String, dynamic>;

        expect(body['channel_id'], equals('C9'));
        expect(body.containsKey('title'), isFalse);
      });
    });

    group('editCanvas', () {
      test('sends POST to canvases.edit with changes', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slackClient.editCanvas(
          canvasId: 'F1',
          changes: [
            {
              'operation': 'replace',
              'document_content': {'type': 'markdown', 'markdown': 'new'},
            },
          ],
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
        final changes = body['changes'] as List<dynamic>;

        expect(uri, equals(SlackUrls.canvasesEdit));
        expect(body['canvas_id'], equals('F1'));
        expect(changes, hasLength(1));
        expect(
          (changes.first as Map<String, dynamic>)['operation'],
          equals('replace'),
        );
      });
    });

    group('deleteCanvas', () {
      test('sends POST to canvases.delete', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slackClient.deleteCanvas(canvasId: 'F1');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final uri = captured[0] as Uri;
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;

        expect(uri, equals(SlackUrls.canvasesDelete));
        expect(body['canvas_id'], equals('F1'));
      });
    });

    group('filesInfo', () {
      test('sends GET to files.info with the file id', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'file': {'id': 'F1', 'filetype': 'canvas'},
            }),
            200,
          ),
        );

        final json = await slackClient.filesInfo(file: 'F1');

        expect((json['file'] as Map<String, dynamic>)['id'], equals('F1'));
        final uri =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.first
                as Uri;
        expect(uri.path, equals(SlackUrls.filesInfo.path));
        expect(uri.queryParameters['file'], equals('F1'));
      });
    });

    group('downloadFile', () {
      test('returns the raw body for a 2xx response', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('# Canvas body', 200));

        final body = await slackClient.downloadFile(
          Uri.parse('https://files.slack.com/c-F1'),
        );

        expect(body, equals('# Canvas body'));
      });

      test('throws SlackApiException on a non-2xx response', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async => http.Response('nope', 403));

        expect(
          () => slackClient.downloadFile(
            Uri.parse('https://files.slack.com/c-F1'),
          ),
          throwsA(isA<SlackApiException>()),
        );
      });

      test(
        'throws not_authorized for a 200 HTML response (text/html header)',
        () async {
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              '<!doctype html><html><body>Sign in to Slack</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          );

          expect(
            () => slackClient.downloadFile(
              Uri.parse('https://files.slack.com/c-F1'),
            ),
            throwsA(
              isA<SlackApiException>().having(
                (e) => e.error,
                'error',
                'not_authorized',
              ),
            ),
          );
        },
      );

      test(
        'throws not_authorized when the body sniffs as HTML without a '
        'content-type header',
        () async {
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              '  <!DOCTYPE HTML>\n<html><head><title>Slack</title></head>',
              200,
            ),
          );

          expect(
            () => slackClient.downloadFile(
              Uri.parse('https://files.slack.com/c-F1'),
            ),
            throwsA(
              isA<SlackApiException>().having(
                (e) => e.error,
                'error',
                'not_authorized',
              ),
            ),
          );
        },
      );
    });

    group('getUploadUrlExternal', () {
      test('sends filename and length as query params', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'upload_url': 'https://files.slack.com/upload/v1/abc',
              'file_id': 'F123',
            }),
            200,
          ),
        );

        final json = await slackClient.getUploadUrlExternal(
          filename: 'notes.txt',
          length: 42,
        );

        expect(json['file_id'], equals('F123'));
        final uri =
            verify(
                  () => httpClient.get(
                    captureAny(),
                    headers: any(named: 'headers'),
                  ),
                ).captured.single
                as Uri;
        expect(uri.path, equals(SlackUrls.filesGetUploadURLExternal.path));
        expect(uri.queryParameters['filename'], equals('notes.txt'));
        expect(uri.queryParameters['length'], equals('42'));
      });
    });

    group('uploadFileBytes', () {
      test('posts the file bytes as multipart form data', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode('OK')),
            200,
          ),
        );

        final uploadUrl = Uri.parse('https://files.slack.com/upload/v1/abc');
        await slackClient.uploadFileBytes(
          uploadUrl: uploadUrl,
          bytes: utf8.encode('hello'),
          filename: 'notes.txt',
        );

        final request =
            verify(() => httpClient.send(captureAny())).captured.single
                as http.MultipartRequest;
        expect(request.url, equals(uploadUrl));
        expect(request.files.single.field, equals('file'));
        expect(request.files.single.filename, equals('notes.txt'));
      });

      test('throws SlackApiException on a non-2xx response', () async {
        when(() => httpClient.send(any())).thenAnswer(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode('nope')),
            500,
          ),
        );

        expect(
          () => slackClient.uploadFileBytes(
            uploadUrl: Uri.parse('https://files.slack.com/upload/v1/abc'),
            bytes: utf8.encode('hello'),
            filename: 'notes.txt',
          ),
          throwsA(isA<SlackApiException>()),
        );
      });
    });

    group('completeUploadExternal', () {
      test(
        'sends the file id, title, channel, thread, and comment',
        () async {
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => http.Response(
              jsonEncode({'ok': true, 'files': <Map<String, dynamic>>[]}),
              200,
            ),
          );

          await slackClient.completeUploadExternal(
            fileId: 'F123',
            filename: 'notes.txt',
            channel: 'C1',
            threadTs: '1.0',
            initialComment: 'here you go',
          );

          final captured = verify(
            () => httpClient.post(
              captureAny(),
              headers: any(named: 'headers'),
              body: captureAny(named: 'body'),
            ),
          ).captured;
          expect(captured[0], equals(SlackUrls.filesCompleteUploadExternal));
          final body =
              jsonDecode(captured[1] as String) as Map<String, dynamic>;
          final files = (body['files'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(files.single['id'], equals('F123'));
          expect(files.single['title'], equals('notes.txt'));
          expect(body['channel_id'], equals('C1'));
          expect(body['thread_ts'], equals('1.0'));
          expect(body['initial_comment'], equals('here you go'));
        },
      );

      test('omits optional fields when absent', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'files': <Map<String, dynamic>>[]}),
            200,
          ),
        );

        await slackClient.completeUploadExternal(
          fileId: 'F123',
          filename: 'notes.txt',
        );

        final body =
            jsonDecode(
                  verify(
                        () => httpClient.post(
                          any(),
                          headers: any(named: 'headers'),
                          body: captureAny(named: 'body'),
                        ),
                      ).captured.single
                      as String,
                )
                as Map<String, dynamic>;
        expect(body.containsKey('channel_id'), isFalse);
        expect(body.containsKey('thread_ts'), isFalse);
        expect(body.containsKey('initial_comment'), isFalse);
      });
    });
  });
}
