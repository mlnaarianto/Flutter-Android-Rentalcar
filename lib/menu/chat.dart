import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:rentalcar/config/api_config.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String currentUserName;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatarUrl;
  final String authToken;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.currentUserName,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatarUrl,
    required this.authToken,
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

  // 🟢 State untuk private channel auth handshake (Pusher/Reverb protocol).
  // socket_id didapat dari server SETELAH koneksi terbentuk, dan wajib
  // dikirim ke endpoint /broadcasting/auth Laravel sebelum kita boleh
  // subscribe ke channel yang bertipe "private-*".
  String? _socketId;
  bool _isSubscribed = false;

  // 🟢 id numeric ASLI dari tabel chats, hasil resolve dari
  // widget.chatId (yang bisa saja berupa room_identifier string custom,
  // bukan id numeric). WAJIB dipakai untuk nama channel Reverb, karena
  // MessageSent::broadcastOn() di server SELALU broadcast ke
  // "chat.{id_numeric_asli}" (lihat ChatController::sendMessage() ->
  // $realChatId = $chat->id). Kalau kita subscribe pakai widget.chatId
  // yang bukan id numeric, nama channel yang kita dengarkan akan beda
  // dengan yang di-broadcast server -> event tidak akan pernah sampai
  // walau proses auth-nya sendiri sukses (200 OK).
  String? _realChatId;

  static const String _avatarHeroTag = 'chat-receiver-avatar';

  static const Color _primaryColor = Color(0xFF2563EB);
  static const Color _bgColor = Color(0xFFF4F6F9);
  static const Color _myBubbleColor = Color(0xFFDCEBFF);

  // 🟢 Konfigurasi Reverb.
  // Sesuaikan lagi kalau IP LAN laptop kamu berubah (cek dengan `ipconfig`
  // di Windows -> lihat "IPv4 Address" di adapter WiFi yang aktif).
  // Kalau test di ANDROID EMULATOR, ganti host jadi '10.0.2.2'.
  // Kalau test di HP FISIK yang konek ke WiFi yang sama dengan laptop,
  // pakai IP LAN laptop (harus sama dengan REVERB_HOST di .env Laravel).
  static const String _reverbHost = '192.168.189.4';
  static const String _reverbPort = '9090';
  static const String _reverbAppKey = '27d6a6d4761caf333da8';

  // 🟢 Endpoint auth untuk private channel.
  // Route /broadcasting/auth didaftarkan lewat withBroadcasting() di
  // bootstrap/app.php, TERPISAH dari grup routes/api.php. Jadi kalau
  // ApiConfig.baseUrl sudah mengandung suffix "/api" (mis. untuk endpoint
  // /messages, /chats/{id}/messages di file ini), suffix itu harus
  // dilepas dulu di sini supaya tidak salah jadi /api/broadcasting/auth
  // (yang akan 404 karena route-nya memang tidak ada di path itu).
  String get _broadcastAuthUrl {
    String base = ApiConfig.baseUrl;
    if (base.endsWith('/api/')) {
      base = base.substring(0, base.length - 5);
    } else if (base.endsWith('/api')) {
      base = base.substring(0, base.length - 4);
    }
    return '$base/broadcasting/auth';
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

    // 🟢 resolve id numeric asli DULU, baru buka koneksi
    // WebSocket + subscribe. Ini memastikan nama channel yang kita
    // dengarkan ("private-chat.{id_numeric}") konsisten dengan channel
    // yang di-broadcast server.
    _resolveRealChatId().then((_) => _initReverbWebSocket());
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialMessages() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/chats/${widget.chatId}/messages'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      debugPrint("FETCH MESSAGES STATUS: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List fetchedMessages = data['data'] ?? [];
        setState(() {
          _messages.clear();
          for (var msg in fetchedMessages) {
            _messages.add({
              'id': msg['id'],
              'text': msg['text'],
              'sender_id': msg['sender_id'].toString(),
              'sender_name': msg['sender_name'] ?? '',
              'created_at': msg['created_at'],
            });
          }
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        debugPrint("FETCH MESSAGES BODY: ${response.body}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Gagal memuat pesan: $e");
      setState(() => _isLoading = false);
    }
  }

  /// 🟢 resolve widget.chatId (id numeric ATAU room_identifier
  /// string custom) menjadi id numeric asli dari tabel chats, lewat
  /// endpoint GET /chats/{chatId}/resolve.
  ///
  /// Kalau room memang belum pernah dibuat sama sekali (belum ada pesan
  /// pertama dikirim), server akan balas chat_id: null. Dalam kasus itu
  /// kita fallback pakai widget.chatId apa adanya (subscribe mungkin
  /// gagal untuk sementara, tapi begitu pesan pertama terkirim dan room
  /// baru dibuat, _sendMessage() akan re-resolve & re-subscribe otomatis).
  Future<void> _resolveRealChatId() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/chats/${widget.chatId}/resolve'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      debugPrint('RESOLVE CHAT ID STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final resolved = data['chat_id'];
        _realChatId = resolved?.toString();
        debugPrint('Real chat_id resolved: $_realChatId (dari widget.chatId: ${widget.chatId})');
      } else {
        debugPrint('RESOLVE CHAT ID BODY: ${response.body}');
      }
    } catch (e) {
      debugPrint('Gagal resolve chat_id: $e');
    }
  }

  /// 🟢 Implementasi WebSocket murni menggunakan package web_socket_channel
  /// ke Reverb, dengan private channel auth handshake:
  /// 1. Buka koneksi WS mentah.
  /// 2. Tunggu event "pusher:connection_established" untuk dapat socket_id.
  /// 3. Panggil _subscribeToPrivateChannel() -> minta signature auth ke
  ///    Laravel, baru kirim frame pusher:subscribe dengan nama channel
  ///    yang benar ("private-chat.{id_numeric_asli}") plus field "auth"
  ///    dari response.
  ///
  /// Tanpa langkah 2-3 ini, Reverb akan menolak/mengabaikan subscription
  /// ke channel private, sehingga event message.sent / message.deleted
  /// tidak akan pernah diterima klien walau koneksi WS-nya sendiri terbuka.
  void _initReverbWebSocket() {
    try {
      final wsUrl =
          'ws://$_reverbHost:$_reverbPort/app/$_reverbAppKey?protocol=7&client=js&version=8.4.0';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel?.stream.listen((message) {
        Map<String, dynamic> decoded;
        try {
          decoded = jsonDecode(message);
        } catch (e) {
          debugPrint('Gagal parse pesan WS: $e');
          return;
        }

        final event = decoded['event'];

        // 1. Koneksi baru terbentuk -> server kasih socket_id.
        //    Baru dari sini kita boleh mulai proses auth handshake.
        if (event == 'pusher:connection_established') {
          final connData = jsonDecode(decoded['data']);
          _socketId = connData['socket_id'];
          debugPrint('Reverb connected. socket_id: $_socketId');
          _subscribeToPrivateChannel();
          return;
        }

        if (event == 'pusher:subscription_succeeded') {
          _isSubscribed = true;
          debugPrint('✅ Subscribed ke channel: ${decoded['channel']}');
          return;
        }

        if (event == 'pusher:error' || event == 'pusher:subscription_error') {
          debugPrint('❌ Reverb error: $decoded');
          return;
        }

        // 2. Event pesan baru dari room chat ini.
        if (event == 'message.sent') {
          final payload = jsonDecode(decoded['data']);
          final msgData = payload['message'];

          if (msgData['sender_id'].toString() != widget.currentUserId) {
            setState(() {
              _messages.add({
                'id': msgData['id'],
                'text': msgData['text'],
                'sender_id': msgData['sender_id'].toString(),
                'sender_name': msgData['sender_name'] ?? '',
                'created_at': msgData['created_at'],
              });
            });
            _scrollToBottom();
          }
          return;
        }

        // 3. 🟢 BARU: pesan dihapus oleh lawan chat (hard delete di server).
        // Cocokkan berdasarkan 'id' lalu hilangkan dari layar kita juga
        // supaya tampilan tetap sinkron dengan database.
        if (event == 'message.deleted') {
          final payload = jsonDecode(decoded['data']);
          final deletedId = payload['message_id'];
          debugPrint('🗑️ Pesan dihapus dari server: $deletedId');
          setState(() {
            _messages.removeWhere((m) => m['id'] == deletedId);
          });
          return;
        }
      }, onError: (error) {
        debugPrint("WebSocket Error: $error");
      }, onDone: () {
        debugPrint("WebSocket ditutup oleh server/koneksi terputus.");
        _isSubscribed = false;
      });
    } catch (e) {
      debugPrint("Gagal konek WebSocket Reverb: $e");
    }
  }

  /// 🟢 Auth handshake untuk private channel.
  /// Channel "chat.{id}" didaftarkan di routes/channels.php sebagai
  /// PrivateChannel, artinya nama channel sebenarnya di level protokol
  /// adalah "private-chat.{id}" dan WAJIB disertai signature "auth" yang
  /// didapat dari POST ke endpoint /broadcasting/auth Laravel.
  ///
  /// 🟢 nama channel pakai (_realChatId ?? widget.chatId)
  /// -> mengutamakan id numeric asli hasil resolve, supaya selalu match
  /// dengan channel yang di-broadcast MessageSent::broadcastOn() di server.
  /// Fallback ke widget.chatId cuma dipakai kalau resolve gagal/room belum
  /// pernah dibuat sama sekali.
  Future<void> _subscribeToPrivateChannel() async {
    if (_socketId == null) {
      debugPrint('Tidak bisa subscribe: socket_id belum tersedia.');
      return;
    }

    final targetChatId = _realChatId ?? widget.chatId;
    final channelName = 'private-chat.$targetChatId';

    debugPrint('Subscribe ke channel: $channelName');

    try {
      final authResponse = await http.post(
        Uri.parse(_broadcastAuthUrl),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
        body: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      debugPrint('BROADCAST AUTH STATUS: ${authResponse.statusCode}');

      if (authResponse.statusCode != 200) {
        debugPrint('BROADCAST AUTH BODY: ${authResponse.body}');
        return;
      }

      final authData = jsonDecode(authResponse.body);
      final authSignature = authData['auth'];

      if (authSignature == null) {
        debugPrint('Response auth tidak mengandung field "auth": $authData');
        return;
      }

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

    // 🟢 id sementara (negatif, dari timestamp) untuk pesan optimistik yang
    // belum dapat id asli dari server. Dipakai supaya _deleteMessage() bisa
    // tahu pesan ini "belum siap dihapus" (lihat pengecekan di bawah), dan
    // supaya key 'id' selalu ada di setiap item _messages tanpa terkecuali.
    final tempId = DateTime.now().millisecondsSinceEpoch * -1;

    final tempMessage = {
      'id': tempId,
      'text': messageText,
      'sender_id': widget.currentUserId,
      'sender_name': widget.currentUserName,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/messages'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'chat_id': widget.chatId,
          'receiver_id': widget.receiverId,
          'text': messageText,
        }),
      );

      // 🟢 Debug logging: lihat langsung status & isi respons server
      // kalau ada masalah lagi ke depannya, ini kunci untuk tahu
      // penyebab pastinya (401/422/500) tanpa nebak-nebak.
      debugPrint("SEND MESSAGE STATUS: ${response.statusCode}");
      debugPrint("SEND MESSAGE BODY: ${response.body}");

      if (response.statusCode != 201) {
        throw Exception('Gagal mengirim ke server (${response.statusCode})');
      }

      final data = jsonDecode(response.body);

      // 🟢 BARU: begitu server balas sukses, ganti id sementara (negatif)
      // di _messages dengan id ASLI dari database. Tanpa ini, pesan yang
      // baru kita kirim sendiri tidak akan pernah bisa dihapus (karena
      // endpoint DELETE /messages/{id} butuh id numeric asli).
      final sentMessage = data['data'];
      final realMessageId = sentMessage?['id'];
      if (realMessageId != null && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx]['id'] = realMessageId;
          }
        });
      }

      // 🟢 kalau ini pesan PERTAMA di room (sebelumnya
      // _realChatId masih null karena room belum ada saat resolve
      // dipanggil di initState), sekarang room-nya sudah pasti dibuat
      // oleh firstOrCreate() di server. Re-resolve & re-subscribe supaya
      // sesi ini juga langsung ikut mendengarkan channel yang benar
      // tanpa perlu keluar-masuk halaman chat dulu.
      if (_realChatId == null) {
        final newChatId = sentMessage?['chat_id'];
        if (newChatId != null) {
          _realChatId = newChatId.toString();
          debugPrint('Room baru dibuat, chat_id: $_realChatId. Re-subscribe...');
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    }
  }

  /// 🟢 BARU: hapus pesan secara permanen lewat DELETE /messages/{id}.
  /// Hard delete di server -> begitu sukses, pesan hilang dari database
  /// dan tidak bisa dikembalikan. UI dihapus dulu secara optimistik,
  /// lalu di-rollback kalau ternyata request-nya gagal.
  Future<void> _deleteMessage(Map<String, dynamic> data) async {
    final messageId = data['id'];

    // Pesan yang masih pakai id sementara (negatif) berarti belum
    // dikonfirmasi server -> jangan biarkan dihapus dulu supaya tidak
    // salah kirim request ke /messages/null atau /messages/-123.
    if (messageId == null || (messageId is int && messageId < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tunggu pesan terkirim dulu sebelum menghapus.')),
      );
      return;
    }

    final removedIndex = _messages.indexOf(data);
    setState(() {
      _messages.remove(data);
    });

    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/messages/$messageId'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      debugPrint("DELETE MESSAGE STATUS: ${response.statusCode}");
      debugPrint("DELETE MESSAGE BODY: ${response.body}");

      if (response.statusCode != 200) {
        // rollback kalau gagal (mis. 403 karena bukan pesan sendiri, atau
        // 404 karena sudah dihapus lebih dulu dari device lain)
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
      debugPrint("Gagal hapus pesan: $e");
      if (mounted) {
        setState(() {
          _messages.insert(removedIndex.clamp(0, _messages.length), data);
        });
      }
    }
  }

  /// 🟢 BARU: bottom sheet konfirmasi hapus, muncul saat pesan (milik
  /// sendiri) ditekan lama. Server memang membatasi hanya sender yang
  /// boleh hapus (lihat ChatController::deleteMessage), jadi sheet ini
  /// hanya dipanggil untuk pesan isMe (lihat onLongPress di build()).
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
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text('Hapus pesan', style: TextStyle(color: Colors.red)),
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
    final bool hasAvatar =
        widget.receiverAvatarUrl != null && widget.receiverAvatarUrl!.isNotEmpty;

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
                  backgroundImage: hasAvatar
                      ? NetworkImage(widget.receiverAvatarUrl!)
                      : null,
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _primaryColor))
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
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final data = _messages[index];
                          final String text = data['text'] ?? '';
                          final String senderId = data['sender_id']?.toString() ?? '';

                          bool isMe = senderId == widget.currentUserId;

                          String timeString = "";
                          DateTime? dateTime;
                          var rawTime = data['created_at'];
                          if (rawTime != null) {
                            dateTime = DateTime.tryParse(rawTime.toString());
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
                                final prevDate = DateTime.tryParse(prevRaw.toString());
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                // 🟢 BARU: bungkus bubble dengan GestureDetector agar
                                // bisa ditekan lama (long press) untuk memunculkan opsi
                                // hapus. Hanya aktif untuk pesan milik sendiri (isMe),
                                // sesuai batasan di server (ChatController::deleteMessage).
                                child: GestureDetector(
                                  onLongPress: isMe ? () => _showDeleteOptions(data) : null,
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                                    ),
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isMe ? _myBubbleColor : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(14),
                                        topRight: const Radius.circular(14),
                                        bottomLeft: Radius.circular(isMe ? 14 : 4),
                                        bottomRight: Radius.circular(isMe ? 4 : 14),
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
                      constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
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
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
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