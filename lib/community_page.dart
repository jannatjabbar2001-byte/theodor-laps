import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

typedef CommunityGet = Future<dynamic> Function(String path);
typedef CommunityWrite = Future<dynamic> Function(
  String path,
  Map<String, dynamic> body,
);
typedef CommunityAvatarUpload = Future<dynamic> Function(String path, XFile image);
typedef CommunityImageHeaders = Future<Map<String, String>> Function();

enum _CommunitySection { publicChat, inbox, members }

class CommunityPage extends StatefulWidget {
  final CommunityGet onGet;
  final CommunityWrite onPost;
  final CommunityWrite onPut;
  final CommunityAvatarUpload? onAvatarUpload;
  final CommunityImageHeaders? onImageHeaders;
  final String apiBaseUrl;

  const CommunityPage({
    required this.onGet,
    required this.onPost,
    required this.onPut,
    this.onAvatarUpload,
    this.onImageHeaders,
    this.apiBaseUrl = '',
    super.key,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  static const _teal = Color(0xff0f9f95);
  static const _ink = Color(0xff18312f);
  static const _muted = Color(0xff71827f);
  static const _line = Color(0xffe4ece9);
  static const _canvas = Color(0xfff4f8f6);
  static const _emojis = ['😀', '😂', '🥰', '👍', '👏', '✨', '❤️', '🙏'];

  final _composer = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _pollTimer;
  Timer? _searchTimer;

  _CommunitySection _section = _CommunitySection.publicChat;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic>? _conversation;
  Map<String, dynamic>? _replyTo;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  Map<String, String> _imageHeaders = const {};
  String? _error;
  int _newMessages = 0;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _polling = false;
  bool _searching = false;
  bool _connected = false;
  bool _mobileChatOpen = false;

  int? get _conversationId => _conversation?['id'] as int?;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    _composer.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);
  List<Map<String, dynamic>> _maps(dynamic value) =>
      (value as List).map(_map).toList();

  String? _avatarUrl(Map<String, dynamic> user) {
    final path = user['avatar_url'];
    if (path is! String || path.isEmpty || widget.apiBaseUrl.isEmpty) return null;
    return '${widget.apiBaseUrl}$path';
  }

  Widget _avatar(Map<String, dynamic> user, {double size = 42}) => _Avatar(
    name: user['display_name']?.toString() ?? 'عضو',
    size: size,
    imageUrl: _avatarUrl(user),
    headers: _imageHeaders,
  );

  Future<void> _initialize() async {
    setState(() => _loading = true);
    try {
      final imageHeaders =
          await widget.onImageHeaders?.call() ?? const <String, String>{};
      final response = await Future.wait([
        widget.onGet('/community/profile'),
        widget.onGet('/community/conversations'),
        widget.onGet('/community/users'),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = _map(response[0]);
        _imageHeaders = imageHeaders;
        _conversations = _maps(response[1]);
        _users = _maps(response[2]);
        _connected = true;
        _error = null;
      });
      await _refreshMessages(initial: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _connected = false;
          _error = 'تعذر تحميل المجتمع. تحقق من الاتصال ثم أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted || _loading || _polling) return;
    _polling = true;
    try {
      await _refreshMessages();
      final conversations = await widget.onGet('/community/conversations');
      if (mounted) {
        setState(() {
          _conversations = _maps(conversations);
          _connected = true;
        });
      }
    } catch (_) {
      if (mounted && _connected) setState(() => _connected = false);
    } finally {
      _polling = false;
    }
  }

  String _messagePath({int? beforeId, int? afterId}) {
    final query = beforeId != null
        ? '?before_id=$beforeId&limit=40'
        : afterId != null
        ? '?after_id=$afterId&limit=80'
        : '?limit=40';
    if (_section == _CommunitySection.inbox && _conversationId != null) {
      return '/community/conversations/$_conversationId/messages$query';
    }
    return '/community/messages$query';
  }

  Future<void> _refreshMessages({bool initial = false}) async {
    if (_section == _CommunitySection.inbox && _conversationId == null) return;
    if (_messages.isNotEmpty && !initial) {
      final lastId = _messages.last['id'] as int;
      final incoming = _maps(await widget.onGet(_messagePath(afterId: lastId)));
      if (!mounted || incoming.isEmpty) return;
      final atLatest = !_scroll.hasClients || _scroll.position.pixels < 90;
      setState(() {
        _messages = [..._messages, ...incoming];
        if (_section == _CommunitySection.publicChat && !atLatest) {
          _newMessages += incoming.length;
        }
      });
      if (atLatest) _scrollToLatest();
      return;
    }
    final latest = await widget.onGet(_messagePath());
    if (!mounted) return;
    setState(() {
      _messages = _maps(latest);
      _newMessages = 0;
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final older = _maps(
        await widget.onGet(
          _messagePath(beforeId: _messages.first['id'] as int),
        ),
      );
      if (mounted && older.isNotEmpty)
        setState(() => _messages = [...older, ..._messages]);
    } catch (_) {
      if (mounted) _notice('تعذر تحميل الرسائل السابقة');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    final replyTo = _replyTo;
    final path = _section == _CommunitySection.inbox && _conversationId != null
        ? '/community/conversations/$_conversationId/messages'
        : '/community/messages';
    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{'body': text};
      if (replyTo != null) payload['reply_to_id'] = replyTo['id'];
      final message = _map(await widget.onPost(path, payload));
      if (!mounted) return;
      _composer.clear();
      setState(() {
        if (_replyTo?['id'] == replyTo?['id']) _replyTo = null;
        if (!_messages.any((item) => item['id'] == message['id'])) {
          _messages = [..._messages, message];
        }
        _newMessages = 0;
        _error = null;
      });
      _scrollToLatest();
      unawaited(_refreshConversations());
    } catch (_) {
      if (mounted) _notice('تعذر إرسال الرسالة. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _selectReply(Map<String, dynamic> message) {
    final sender = _map(message['sender']);
    setState(() {
      _replyTo = {
        'id': message['id'],
        'body': message['body'],
        'sender_name': sender['display_name']?.toString() ?? 'عضو',
      };
    });
  }

  Future<void> _refreshConversations() async {
    try {
      final result = await widget.onGet('/community/conversations');
      if (mounted) setState(() => _conversations = _maps(result));
    } catch (_) {}
  }

  void _searchUsers(String query) {
    _searchTimer?.cancel();
    _searchQuery = query.trim();
    _searchTimer = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final value = await widget.onGet(
          '/community/users?search=${Uri.encodeQueryComponent(_searchQuery)}',
        );
        if (mounted) setState(() => _users = _maps(value));
      } catch (_) {
        if (mounted) _notice('تعذر البحث عن الأعضاء');
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _startConversation(Map<String, dynamic> user) async {
    try {
      final result = _map(
        await widget.onPost('/community/conversations', {
          'user_id': user['id'],
        }),
      );
      if (!mounted) return;
      setState(() {
        _conversation = result;
        _section = _CommunitySection.inbox;
        _mobileChatOpen = true;
        _messages = [];
        _replyTo = null;
      });
      await _refreshMessages(initial: true);
      await _refreshConversations();
    } catch (_) {
      if (mounted) _notice('تعذر بدء المحادثة الخاصة');
    }
  }

  void _openConversation(Map<String, dynamic> item) {
    setState(() {
      _conversation = item;
      _section = _CommunitySection.inbox;
      _mobileChatOpen = true;
      _messages = [];
      _replyTo = null;
    });
    unawaited(_refreshMessages(initial: true));
  }

  void _selectSection(_CommunitySection section) {
    setState(() {
      _section = section;
      _replyTo = null;
      if (section != _CommunitySection.inbox) _mobileChatOpen = false;
      if (section == _CommunitySection.publicChat) _conversation = null;
    });
    if (section == _CommunitySection.publicChat) {
      _messages = [];
      unawaited(_refreshMessages(initial: true));
    } else if (section == _CommunitySection.inbox && _conversation != null) {
      _messages = [];
      unawaited(_refreshMessages(initial: true));
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final upload = widget.onAvatarUpload;
    if (upload == null) {
      _notice('رفع الصور غير متاح في بيئة الاختبار');
      return;
    }
    try {
      const imageTypes = XTypeGroup(
        label: 'images',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      final image = await openFile(acceptedTypeGroups: [imageTypes]);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        _notice('يجب ألا يتجاوز حجم الصورة 2 ميغابايت');
        return;
      }
      final profile = _map(
        await upload('/community/profile/avatar', image),
      );
      if (!mounted) return;
      setState(() => _profile = profile);
      unawaited(_loadUsers(_searchQuery));
      unawaited(_refreshConversations());
      unawaited(_refreshMessages(initial: true));
      _notice('تم تحديث الصورة الشخصية');
    } catch (_) {
      if (mounted) _notice('تعذر رفع الصورة. تحقق من النوع والحجم.');
    }
  }

  Future<void> _editProfile() async {
    final controller = TextEditingController(
      text: _profile['display_name']?.toString() ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اسمك في المجتمع'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final profile = _map(
        await widget.onPut('/community/profile', {'display_name': name.trim()}),
      );
      if (mounted) setState(() => _profile = profile);
      _searchUsers(_searchQuery);
    } catch (_) {
      if (mounted) _notice('اكتب اسمًا من حرفين إلى 40 حرفًا');
    }
  }

  Future<void> _showUser(Map<String, dynamic> user) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _avatar(user, size: 54),
              const SizedBox(height: 10),
              Text(
                user['display_name']?.toString() ?? 'عضو',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                _roleLabel(user['role']?.toString()),
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    unawaited(_startConversation(user));
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('بدء محادثة خاصة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleLabel(String? role) => switch (role) {
    'superadmin' => 'مدير المجتمع',
    'admin' || 'supervisor' => 'مشرف',
    _ => 'عضو في Theodore Labs',
  };

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final compactChat =
        !wide && _section == _CommunitySection.inbox && _mobileChatOpen;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          elevation: 0,
          leading: compactChat
              ? IconButton(
                  tooltip: 'العودة للمحادثات',
                  onPressed: () => setState(() => _mobileChatOpen = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.forum_outlined, color: _teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      compactChat
                          ? _map(
                                  _conversation!['user'],
                                )['display_name']?.toString() ??
                                'محادثة خاصة'
                          : 'المجتمع',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _connected ? 'متصل بالمجتمع' : 'إعادة الاتصال…',
                      style: TextStyle(
                        fontSize: 11,
                        color: _connected ? _teal : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'الأعضاء',
              onPressed: () => _selectSection(_CommunitySection.members),
              icon: const Icon(Icons.search_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'إعدادات المجتمع',
              onSelected: (value) {
                if (value == 'profile') {
                  unawaited(_editProfile());
                } else if (value == 'avatar') {
                  unawaited(_pickAndUploadAvatar());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'profile',
                  child: Text('تعديل الاسم الظاهر'),
                ),
                PopupMenuItem(
                  value: 'avatar',
                  child: Text('تغيير الصورة الشخصية'),
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _loading && _profile.isEmpty
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 820) {
                    return Row(
                      children: [
                        SizedBox(width: 318, child: _sidebar()),
                        const VerticalDivider(width: 1, color: _line),
                        Expanded(child: _desktopContent()),
                      ],
                    );
                  }
                  return _mobileContent();
                },
              ),
        bottomNavigationBar: !wide && !compactChat
            ? NavigationBar(
                selectedIndex: _section.index,
                onDestinationSelected: (index) =>
                    _selectSection(_CommunitySection.values[index]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.forum_outlined),
                    label: 'العامة',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_outlined),
                    label: 'الرسائل',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline_rounded),
                    label: 'الأعضاء',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _sidebar() => ColoredBox(
    color: Colors.white,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _searchField(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _sectionButton(
                _CommunitySection.publicChat,
                'العامة',
                Icons.forum_outlined,
              ),
              _sectionButton(
                _CommunitySection.inbox,
                'الرسائل',
                Icons.chat_outlined,
              ),
              _sectionButton(
                _CommunitySection.members,
                'الأعضاء',
                Icons.people_outline,
              ),
            ],
          ),
        ),
        const Divider(height: 20, color: _line),
        Expanded(child: _sidebarList()),
        _currentUserTile(),
      ],
    ),
  );

  Widget _searchField() => TextField(
    controller: _search,
    onChanged: _searchUsers,
    decoration: InputDecoration(
      hintText: 'ابحث عن عضو',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: _searching
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _search.text.isNotEmpty
          ? IconButton(
              tooltip: 'مسح البحث',
              onPressed: () {
                _search.clear();
                _searchUsers('');
              },
              icon: const Icon(Icons.close_rounded),
            )
          : null,
      filled: true,
      fillColor: _canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
  );

  Widget _sectionButton(
    _CommunitySection section,
    String label,
    IconData icon,
  ) {
    final selected = _section == section;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectSection(section),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
            decoration: BoxDecoration(
              color: selected
                  ? _teal.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, size: 19, color: selected ? _teal : _muted),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected ? _teal : _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarList() {
    if (_section == _CommunitySection.publicChat) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Material(
            color: Colors.white,
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xffe0f2ef),
                foregroundColor: _teal,
                child: Icon(Icons.groups_2_outlined),
              ),
              title: const Text(
                'المحادثة العامة',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _messages.isEmpty
                    ? 'ابدأ حديثًا مع المجتمع'
                    : _messages.last['body'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectSection(_CommunitySection.publicChat),
            ),
          ),
        ],
      );
    }
    if (_section == _CommunitySection.inbox) {
      if (_conversations.isEmpty)
        return _emptyList('لا توجد محادثات بعد', Icons.chat_bubble_outline);
      return ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) =>
            _conversationTile(_conversations[index]),
      );
    }
    if (_users.isEmpty)
      return _emptyList(
        _searchQuery.isEmpty ? 'لا يوجد أعضاء لعرضهم' : 'لا توجد نتائج مطابقة',
        Icons.people_outline,
      );
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) => _userTile(_users[index]),
    );
  }

  Widget _conversationTile(Map<String, dynamic> item) {
    final person = _map(item['user']);
    final unread = item['unread_count'] as int? ?? 0;
    return Material(
      color: Colors.white,
      child: ListTile(
        selected: _conversationId == item['id'],
        onTap: () => _openConversation(item),
        leading: _avatar(person),
        title: Text(
          person['display_name']?.toString() ?? 'عضو',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          item['last_message']?.toString() ?? 'ابدأ محادثة خاصة',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: unread > 0
            ? _Badge(count: unread)
            : const Icon(Icons.chevron_left_rounded, color: _muted),
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> user) => Material(
    color: Colors.white,
    child: ListTile(
      onTap: () => unawaited(_showUser(user)),
      leading: _avatar(user),
      title: Text(
        user['display_name']?.toString() ?? 'عضو',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('عضو في المجتمع'),
      trailing: IconButton(
        tooltip: 'محادثة خاصة',
        onPressed: () => unawaited(_startConversation(user)),
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: _teal),
      ),
    ),
  );

  Widget _emptyList(String text, IconData icon) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: _muted),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _currentUserTile() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        _avatar(_profile),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile['display_name']?.toString() ?? 'ملفي في المجتمع',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'حسابك',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'تعديل الاسم الظاهر',
          onPressed: _editProfile,
          icon: const Icon(Icons.tune_rounded, size: 20),
        ),
      ],
    ),
  );

  Widget _desktopContent() {
    if (_section == _CommunitySection.members)
      return _prompt(
        Icons.people_outline_rounded,
        'أعضاء المجتمع',
        'اختر عضوًا من القائمة لعرض ملفه أو بدء محادثة خاصة.',
      );
    if (_section == _CommunitySection.inbox && _conversation == null)
      return _prompt(
        Icons.chat_bubble_outline_rounded,
        'رسائلك الخاصة',
        'اختر محادثة سابقة أو ابحث عن عضو لبدء واحدة.',
      );
    return _chatPane();
  }

  Widget _mobileContent() {
    if (_section == _CommunitySection.publicChat || _mobileChatOpen)
      return _chatPane();
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _searchField(),
          ),
          Expanded(child: _sidebarList()),
        ],
      ),
    );
  }

  Widget _prompt(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _teal, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.6),
          ),
        ],
      ),
    ),
  );

  Widget _chatPane() => Column(
    children: [
      _chatHeader(),
      if (_error != null)
        MaterialBanner(
          content: Text(_error!),
          leading: const Icon(Icons.wifi_off_rounded),
          actions: [
            TextButton(
              onPressed: _initialize,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      Expanded(
        child: _loading && _messages.isEmpty
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : _messages.isEmpty
            ? _emptyChat()
            : Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _messages.length) return _olderButton();
                      final message = _messages[_messages.length - 1 - index];
                      final sender = _map(message['sender']);
                      return _MessageBubble(
                        message: message,
                        avatarUrl: _avatarUrl(sender),
                        avatarHeaders: _imageHeaders,
                        onReply: () => _selectReply(message),
                        onSenderTap: message['is_mine'] == true
                            ? null
                            : () =>
                                  unawaited(_showUser(_map(message['sender']))),
                      );
                    },
                  ),
                  if (_newMessages > 0)
                    PositionedDirectional(
                      bottom: 12,
                      end: 16,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() => _newMessages = 0);
                          _scrollToLatest();
                        },
                        icon: const Icon(Icons.south_rounded, size: 18),
                        label: Text('$_newMessages رسائل جديدة'),
                      ),
                    ),
                ],
              ),
      ),
      _messageInput(),
    ],
  );

  Widget _chatHeader() {
    final private =
        _section == _CommunitySection.inbox && _conversation != null;
    final peer = private ? _map(_conversation!['user']) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (private)
            _avatar(peer!, size: 38)
          else
            const CircleAvatar(
              radius: 19,
              backgroundColor: Color(0xffe0f2ef),
              foregroundColor: _teal,
              child: Icon(Icons.groups_2_outlined),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  private
                      ? (peer?['display_name']?.toString() ?? 'محادثة خاصة')
                      : 'المحادثة العامة',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  private
                      ? 'محادثة خاصة بينكما'
                      : 'رسائل مشتركة مع أعضاء المجتمع',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          if (!private)
            IconButton(
              tooltip: 'عرض الأعضاء',
              onPressed: () => _selectSection(_CommunitySection.members),
              icon: const Icon(Icons.people_outline_rounded),
            ),
        ],
      ),
    );
  }

  Widget _emptyChat() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_outlined, color: _teal, size: 32),
          ),
          const SizedBox(height: 14),
          const Text(
            'المجتمع هادئ الآن',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: _ink,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'ابدأ المحادثة برسالة ترحّب بالجميع.',
            style: TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );

  Widget _olderButton() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Center(
      child: TextButton.icon(
        onPressed: _loadingOlder ? null : _loadOlder,
        icon: _loadingOlder
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.history_rounded, size: 18),
        label: Text(_loadingOlder ? 'جارٍ التحميل' : 'تحميل رسائل أقدم'),
      ),
    ),
  );

  Widget _messageInput() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsetsDirectional.only(
                start: 12,
                end: 4,
                top: 6,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: _canvas,
                borderRadius: BorderRadius.circular(12),
                border: const BorderDirectional(
                  start: BorderSide(color: _teal, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رد على ${_replyTo!['sender_name']}',
                          style: const TextStyle(
                            color: _teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _replyTo!['body']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إلغاء الرد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                tooltip: 'إضافة رمز تعبيري',
                onSelected: (emoji) {
                  final selection = _composer.selection;
                  final offset = selection.isValid
                      ? selection.baseOffset
                      : _composer.text.length;
                  final text = _composer.text.replaceRange(offset, offset, emoji);
                  _composer.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(
                      offset: offset + emoji.length,
                    ),
                  );
                },
                itemBuilder: (_) => _emojis
                    .map(
                      (emoji) => PopupMenuItem(
                        value: emoji,
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    )
                    .toList(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.emoji_emotions_outlined, color: _muted),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter: (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة…',
                    filled: true,
                    fillColor: _canvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 46,
                child: IconButton.filled(
                  tooltip: 'إرسال الرسالة',
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                  ),
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;
  final Map<String, String> headers;
  const _Avatar({
    required this.name,
    this.size = 42,
    this.imageUrl,
    this.headers = const {},
  });
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? 'ع'
        : String.fromCharCode(name.runes.first);
    if (imageUrl != null) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          headers: headers,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CircleAvatar(
            radius: size / 2,
            backgroundColor: const Color(0xffdff0ec),
            foregroundColor: const Color(0xff177b71),
            child: Text(
              initial,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .38),
            ),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xffdff0ec),
      foregroundColor: const Color(0xff177b71),
      child: Text(
        initial,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .38),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const BoxDecoration(
      color: Color(0xff0f9f95),
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback? onSenderTap;
  final VoidCallback? onReply;
  final String? avatarUrl;
  final Map<String, String> avatarHeaders;
  const _MessageBubble({
    required this.message,
    this.onSenderTap,
    this.onReply,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });
  @override
  Widget build(BuildContext context) {
    final mine = message['is_mine'] == true;
    final sender = Map<String, dynamic>.from(message['sender'] as Map);
    final replyTo = message['reply_to'] is Map
        ? Map<String, dynamic>.from(message['reply_to'] as Map)
        : null;
    final name = sender['display_name']?.toString() ?? 'عضو';
    final dateTime = DateTime.tryParse(message['created_at']?.toString() ?? '')
        ?.toLocal();
    final time = dateTime == null
        ? ''
        : '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    final showDate =
        dateTime != null &&
        (dateTime.year != today.year ||
            dateTime.month != today.month ||
            dateTime.day != today.day);
    return GestureDetector(
      onLongPress: onReply,
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width < 600 ? 310 : 480,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine) ...[
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSenderTap,
                    child: _Avatar(
                      name: name,
                      size: 30,
                      imageUrl: avatarUrl,
                      headers: avatarHeaders,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xffd9f2ec) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(mine ? 16 : 5),
                        bottomRight: Radius.circular(mine ? 5 : 16),
                      ),
                      border: Border.all(
                        color: mine
                            ? const Color(0xffcce9e3)
                            : const Color(0xffe6eeeb),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyTo != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 7),
                            padding: const EdgeInsetsDirectional.only(
                              start: 8,
                              end: 6,
                              top: 5,
                              bottom: 5,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? const Color(0xffc9e8e1)
                                  : const Color(0xfff1f6f4),
                              borderRadius: BorderRadius.circular(8),
                              border: const BorderDirectional(
                                start: BorderSide(
                                  color: Color(0xff0f9f95),
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  replyTo['sender_name']?.toString() ?? 'عضو',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xff177b71),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  replyTo['body']?.toString() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xff52645f),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!mine)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: InkWell(
                              onTap: onSenderTap,
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Color(0xff177b71),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        Text(
                          message['body']?.toString() ?? '',
                          style: const TextStyle(
                            height: 1.45,
                            color: Color(0xff18312f),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: Text(
                            showDate
                                ? '${dateTime!.day}/${dateTime.month}/${dateTime.year} · $time'
                                : time,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff73837f),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (mine) const SizedBox(width: 37),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
