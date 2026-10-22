import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkawn_alshamil/community_page.dart';

class _FakeCommunityApi {
  final publicMessages = <Map<String, dynamic>>[];
  final privateMessages = <Map<String, dynamic>>[];
  final conversations = <Map<String, dynamic>>[];
  final postedBodies = <Map<String, dynamic>>[];
  int nextId = 1;

  Future<dynamic> get(String path) async {
    if (path == '/community/profile')
      return {'id': 1, 'display_name': 'مها', 'role': 'user'};
    if (path == '/community/conversations') return conversations;
    if (path.startsWith('/community/users'))
      return [
        {'id': 2, 'display_name': 'ليان', 'role': 'user'},
      ];
    if (path.startsWith('/community/conversations/')) return privateMessages;
    if (path.startsWith('/community/messages')) return publicMessages;
    throw StateError('Unexpected GET $path');
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    postedBodies.add(Map<String, dynamic>.from(body));
    if (path == '/community/conversations') {
      final conversation = {
        'id': 10,
        'user': {'id': body['user_id'], 'display_name': 'ليان', 'role': 'user'},
        'unread_count': 0,
      };
      conversations
        ..clear()
        ..add(conversation);
      return conversation;
    }
    final parent = [
      ...publicMessages,
      ...privateMessages,
    ].where((item) => item['id'] == body['reply_to_id']).firstOrNull;
    final message = {
      'id': nextId++,
      'body': body['body'],
      'reply_to_id': body['reply_to_id'],
      'reply_to': parent == null
          ? null
          : {
              'id': parent['id'],
              'body': parent['body'],
              'sender_name': parent['sender']['display_name'],
            },
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sender': {'id': 1, 'display_name': 'مها'},
      'is_mine': true,
    };
    if (path == '/community/messages') {
      publicMessages.add(message);
    } else if (path == '/community/conversations/10/messages') {
      privateMessages.add(message);
    } else {
      throw StateError('Unexpected POST $path');
    }
    return message;
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async => {
    'id': 1,
    'display_name': body['display_name'],
    'role': 'user',
  };
}

Widget _testApp(_FakeCommunityApi api) => MaterialApp(
  home: CommunityPage(onGet: api.get, onPost: api.post, onPut: api.put),
);

void main() {
  testWidgets('public chat sends a message', (tester) async {
    final api = _FakeCommunityApi();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'مرحبًا بالمجتمع');
    await tester.tap(find.byTooltip('إرسال الرسالة'));
    await tester.pumpAndSettle();
    expect(api.publicMessages, hasLength(1));
    expect(find.text('مرحبًا بالمجتمع'), findsOneWidget);
  });

  testWidgets('public chat replies with the parent message preview', (
    tester,
  ) async {
    final api = _FakeCommunityApi()..nextId = 2;
    api.publicMessages.add({
      'id': 1,
      'body': 'رسالة أصلية',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sender': {'id': 2, 'display_name': 'سارة'},
      'is_mine': false,
    });
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('رسالة أصلية'));
    await tester.pumpAndSettle();
    expect(find.text('رد على سارة'), findsOneWidget);
    expect(find.text('رسالة أصلية'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, 'هذا رد');
    await tester.tap(find.byTooltip('إرسال الرسالة'));
    await tester.pumpAndSettle();

    expect(api.postedBodies.last, {'body': 'هذا رد', 'reply_to_id': 1});
    expect(find.text('رسالة أصلية'), findsNWidgets(2));
  });

  testWidgets('member can start a private chat', (tester) async {
    final api = _FakeCommunityApi();
    await tester.pumpWidget(_testApp(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأعضاء').last);
    await tester.pumpAndSettle();
    expect(find.text('ليان'), findsOneWidget);
    await tester.tap(find.byTooltip('محادثة خاصة'));
    await tester.pumpAndSettle();
    expect(api.conversations, hasLength(1));
    expect(find.text('محادثة خاصة بينكما'), findsOneWidget);
    expect(find.text('اكتب رسالة…'), findsOneWidget);
  });
}
