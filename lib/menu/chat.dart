import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rentalcar/config/api_config.dart';
import 'package:rentalcar/services/api_client.dart'; // 🟢 FASE 5: refresh token otomatis

class ChatPage extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String currentUserName;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatarUrl;
 
  // otomatis oleh ApiClient, jadi tidak perlu dioper dari halaman pemanggil
  // (token yang dioper akan basi kalau chat dibuka lama).

  const ChatPage({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.currentUserName,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatarUrl,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _hasText = false;

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  WebSocketChannel? _channel;

  String? _socketId;
  bool _isSubscribed = false;
  String? _realChatId;

  static const String _avatarHeroTag = 'chat-receiver-avatar';
  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _myBubbleColor = Color(0xFFDCEBFF);

  // ================= KONFIGURASI REVERB =================
  // Port & app key Reverb TIDAK ikut ApiConfig.baseUrl (beda port dari API
  // biasa), jadi tetap dikonstantakan di sini. Tapi HOST dan SKEMA (ws/wss)
  // diturunkan otomatis dari ApiConfig.baseUrl lewat getter _reverbUrl di
  // bawah -- supaya kalau IP di api_config.dart diganti, atau baseUrl sudah
  // pindah ke https:// (production), koneksi WebSocket otomatis ikut tanpa
  // perlu ubah dua tempat terpisah.
  static const String _reverbPort = '9090';
  static const String _reverbAppKey = '27d6a6d4761caf333da8';

  String get _broadcastAuthUrl {
    String base = ApiConfig.baseUrl;
    if (base.endsWith('/api/')) {
      base = base.substring(0, base.length - 5);
    } else if (base.endsWith('/api')) {
      base = base.substring(0, base.length - 4);
    }
    return '$base/broadcasting/auth';
  }

  /// Membentuk URL WebSocket Reverb dari ApiConfig.baseUrl.
  /// - Host diambil dari host baseUrl (mis. 192.168.189.4), bukan hardcode.
  /// - Skema mengikuti baseUrl: http -> ws (aman untuk LAN/dev),
  ///   https -> wss (WAJIB untuk production, supaya isi chat terenkripsi).
  String get _reverbUrl {
    final apiUri = Uri.parse(ApiConfig.baseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final host = apiUri.host;
    return '$scheme://$host:$_reverbPort/app/$_reverbAppKey'
        '?protocol=7&client=js&version=8.4.0';
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });

    _fetchInitialMessages();
    _resolveRealChatId().then((_) {
      // 🟢 FASE 5: kalau halaman sudah ditutup (atau sesi berakhir dan app
      // dipindah ke LoginPage) selama request berjalan, jangan buka
      // WebSocket baru -- tidak akan ada yang menutupnya.
      if (!mounted) return;
      _initReverbWebSocket();
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Menyeragamkan bentuk data pesan dari 3 sumber berbeda (fetch riwayat,
  /// event WebSocket 'message.sent', dan response setelah kirim pesan)
  /// menjadi satu format konsisten yang dipakai UI.
  ///
  /// PENTING: nama pengirim SENGAJA tidak diambil dari field 'sender_name'
  /// backend, karena backend (ChatController::getMessages/sendMessage,
  /// serta payload event MessageSent yang di-broadcast tanpa relasi sender
  /// ter-load) tidak pernah mengirim field flat 'sender_name' itu -- yang
  /// ada hanyalah relasi nested 'sender.name' (kadang bahkan tidak ada sama
  /// sekali di payload socket). Karena room chat ini selalu 1-lawan-1 (lihat
  /// constructor ChatPage: currentUserId vs receiverId), nama pengirim bisa
  /// disimpulkan dengan aman hanya dari sender_id, tanpa bergantung ke
  /// bentuk response backend yang bisa berubah.
  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> raw) {
    final String senderId = raw['sender_id']?.toString() ?? '';
    final String senderName = senderId == widget.currentUserId
        ? widget.currentUserName
        : widget.receiverName;

    return {
      'id': raw['id'],
      'text': raw['text'] ?? '',
      'sender_id': senderId,
      'sender_name': senderName,
      'created_at': raw['created_at'],
    };
  }

  Future<void> _fetchInitialMessages() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/chats/${widget.chatId}/messages'),
      );

      // 🟢 FASE 5: cek mounted setelah await. Dengan refresh token, request
      // bisa lebih lama (refresh + retry), jadi peluang halaman sudah
      // ditutup sebelum respons datang lebih besar.
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List fetchedMessages = data['data'] ?? [];
        setState(() {
          _messages.clear();
          for (var msg in fetchedMessages) {
            _messages.add(_normalizeMessage(Map<String, dynamic>.from(msg)));
          }
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Gagal memuat pesan: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveRealChatId() async {
    try {
      final response = await ApiClient.instance.get(
        Uri.parse('${ApiConfig.baseUrl}/chats/${widget.chatId}/resolve'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resolved = data['chat_id'];
        _realChatId = resolved?.toString();
      }
    } catch (e) {
      debugPrint('Gagal resolve chat_id: $e');
    }
  }

  void _initReverbWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_reverbUrl));

      _channel?.stream.listen((message) {
        Map<String, dynamic> decoded;
        try {
          decoded = jsonDecode(message);
        } catch (e) {
          return;
        }

        final event = decoded['event'];

        if (event == 'pusher:connection_established') {
          final connData = jsonDecode(decoded['data']);
          _socketId = connData['socket_id'];
          _subscribeToPrivateChannel();
          return;
        }

        if (event == 'pusher:subscription_succeeded') {
          _isSubscribed = true;
          return;
        }

        if (event == 'message.sent') {
          final payload = jsonDecode(decoded['data']);
          final normalized = _normalizeMessage(
            Map<String, dynamic>.from(payload['message']),
          );
          final incomingId = normalized['id'];

          setState(() {
            final alreadyExists =
                _messages.any((m) => m['id'] == incomingId);
            if (alreadyExists) return;
            _messages.add(normalized);
          });
          _scrollToBottom();
          return;
        }

        if (event == 'message.deleted') {
          final payload = jsonDecode(decoded['data']);
          final deletedId = payload['message_id'];
          setState(() {
            _messages.removeWhere((m) => m['id'] == deletedId);
          });
          return;
        }
      }, onError: (error) {
        debugPrint("WebSocket Error: $error");
      }, onDone: () {
        _isSubscribed = false;
      });
    } catch (e) {
      debugPrint("Gagal konek WebSocket Reverb: $e");
    }
  }

  Future<void> _subscribeToPrivateChannel() async {
    if (_socketId == null) return;

    final targetChatId = _realChatId ?? widget.chatId;
    final channelName = 'private-chat.$targetChatId';

    try {
      final authResponse = await ApiClient.instance.post(
        Uri.parse(_broadcastAuthUrl),
        body: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      if (!mounted) return;
      if (authResponse.statusCode != 200) return;

      final authData = jsonDecode(authResponse.body);
      final authSignature = authData['auth'];

      if (authSignature == null) return;

      _channel?.sink.add(jsonEncode({
        "event": "pusher:subscribe",
        "data": {
          "channel": channelName,
          "auth": authSignature,
        }
      }));
    } catch (e) {
      debugPrint('Gagal melakukan broadcasting auth: $e');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      // Content-Type JSON tetap diset di sini: ApiClient sengaja tidak
      // mengaturnya (hanya Accept dan Authorization).
      final response = await ApiClient.instance.post(
        Uri.parse('${ApiConfig.baseUrl}/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': widget.chatId,
          'receiver_id': widget.receiverId,
          'text': messageText,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Gagal mengirim ke server (${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      final sentMessage = data['data'];
      final realMessageId = sentMessage?['id'];

      if (realMessageId != null && mounted) {
        setState(() {
          final alreadyExists =
              _messages.any((m) => m['id'] == realMessageId);
          if (!alreadyExists) {
            _messages.add(
              _normalizeMessage(Map<String, dynamic>.from(sentMessage)),
            );
          }
        });
        _scrollToBottom();
      }

      if (_realChatId == null) {
        final newChatId = sentMessage?['chat_id'];
        if (newChatId != null) {
          _realChatId = newChatId.toString();
          _subscribeToPrivateChannel();
        }
      }
    } catch (e) {
      debugPrint("Gagal mengirim pesan: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pesan gagal terkirim. Coba lagi.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> data) async {
    final messageId = data['id'];

    if (messageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID pesan tidak valid.')),
      );
      return;
    }

    final removedIndex = _messages.indexOf(data);
    setState(() {
      _messages.remove(data);
    });

    try {
      final response = await ApiClient.instance.delete(
        Uri.parse('${ApiConfig.baseUrl}/messages/$messageId'),
      );

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _messages.insert(removedIndex.clamp(0, _messages.length), data);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menghapus pesan.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.insert(removedIndex.clamp(0, _messages.length), data);
        });
      }
    }
  }

  void _showDeleteOptions(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text('Hapus pesan',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(data);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Batal'),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String? _hiResAvatarUrl(String? url, {int size = 720}) {
    if (url == null || url.isEmpty) return url;
    final sizePattern = RegExp(r'=s\d+-c(-[a-z0-9]+)?$');
    if (sizePattern.hasMatch(url)) {
      return url.replaceAll(sizePattern, '=s$size-c');
    }
    return url;
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';

    const bulan = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${date.day} ${bulan[date.month - 1]} ${date.year}';
  }

  void _openAvatarViewer() {
    final url = widget.receiverAvatarUrl;
    if (url == null || url.isEmpty) return;

    final hiResUrl = _hiResAvatarUrl(url, size: 720) ?? url;

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _ZoomableImageViewer(
              networkUrl: hiResUrl,
              heroTag: _avatarHeroTag,
              title: widget.receiverName,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasAvatar = widget.receiverAvatarUrl != null &&
        widget.receiverAvatarUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: hasAvatar ? _openAvatarViewer : null,
              child: Hero(
                tag: _avatarHeroTag,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  backgroundImage:
                      hasAvatar ? NetworkImage(widget.receiverAvatarUrl!) : null,
                  child: !hasAvatar
                      ? Text(
                          _initials(widget.receiverName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.receiverName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryColor))
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock_outline_rounded,
                                    size: 30, color: _primaryColor),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                "Pesan aman dan terenkripsi",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Silakan mulai percakapan dengan ${widget.receiverName}.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final data = _messages[index];
                          final String text = data['text'] ?? '';
                          final String senderId =
                              data['sender_id']?.toString() ?? '';

                          bool isMe = senderId == widget.currentUserId;

                          String timeString = "";
                          DateTime? dateTime;
                          var rawTime = data['created_at'];
                          if (rawTime != null) {
                            // .toLocal() WAJIB: Laravel menyimpan & mengirim
                            // timestamp dalam UTC. Tanpa ini, jam yang tampil
                            // di bubble & separator tanggal akan meleset
                            // sejumlah offset timezone server vs device user.
                            dateTime =
                                DateTime.tryParse(rawTime.toString())?.toLocal();
                            if (dateTime != null) {
                              timeString =
                                  "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
                            }
                          }

                          bool showDateSeparator = false;
                          if (dateTime != null) {
                            if (index == 0) {
                              showDateSeparator = true;
                            } else {
                              final prevData = _messages[index - 1];
                              final prevRaw = prevData['created_at'];
                              if (prevRaw != null) {
                                final prevDate =
                                    DateTime.tryParse(prevRaw.toString())
                                        ?.toLocal();
                                if (prevDate != null) {
                                  showDateSeparator = prevDate.year != dateTime.year ||
                                      prevDate.month != dateTime.month ||
                                      prevDate.day != dateTime.day;
                                }
                              }
                            }
                          }

                          return Column(
                            children: [
                              if (showDateSeparator && dateTime != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      _formatDateSeparator(dateTime),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: GestureDetector(
                                  onLongPress:
                                      isMe ? () => _showDeleteOptions(data) : null,
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width * 0.75,
                                    ),
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 13, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isMe ? _myBubbleColor : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(14),
                                        topRight: const Radius.circular(14),
                                        bottomLeft:
                                            Radius.circular(isMe ? 14 : 4),
                                        bottomRight:
                                            Radius.circular(isMe ? 4 : 14),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          text,
                                          style: const TextStyle(
                                            color: Color(0xFF1E293B),
                                            fontSize: 14.5,
                                            height: 1.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              timeString,
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 10,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.done_all_rounded,
                                                size: 13,
                                                color: _primaryColor,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      constraints:
                          const BoxConstraints(minHeight: 44, maxHeight: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _bgColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontSize: 14.5),
                        decoration: InputDecoration(
                          hintText: "Ketik pesan...",
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _hasText ? _primaryColor : Colors.grey.shade300,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _hasText ? _sendMessage : null,
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomableImageViewer extends StatefulWidget {
  final String networkUrl;
  final String heroTag;
  final String title;

  const _ZoomableImageViewer({
    required this.networkUrl,
    required this.heroTag,
    required this.title,
  });

  @override
  State<_ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<_ZoomableImageViewer>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_animation != null) {
          _controller.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    Matrix4 endMatrix;
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;

    if (_controller.value != Matrix4.identity()) {
      endMatrix = Matrix4.identity();
    } else {
      endMatrix = Matrix4.identity()
        ..translate(-position.dx * 1.8, -position.dy * 1.8)
        ..scale(2.8);
    }

    _animation = Matrix4Tween(begin: _controller.value, end: endMatrix)
        .animate(CurveTween(curve: Curves.easeOut).animate(_animController));
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: Hero(
            tag: widget.heroTag,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                widget.networkUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Gagal memuat gambar",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}