import 'package:flutter/material.dart';

import '../HomePage/HomePage.dart';

// Static messages storage for demo - in real app replace with backend API
Map<String, List<ChatMessage>> _messagesDatabase = {
  'Alice': [],
  'Bob': [],
  'Charlie': [],
  'David': [],
};

enum MessageStatus { sending, sent, delivered, read }

class ChatPage extends StatefulWidget {
  final String chatUserName;

  ChatPage({required this.chatUserName});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late List<ChatMessage> _userMessages;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _userMessages = _messagesDatabase[widget.chatUserName] ?? [];
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Create new message with sending status
    ChatMessage newMessage = ChatMessage(
      text: text,
      isSentByMe: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    setState(() {
      _userMessages.add(newMessage);
      _messagesDatabase[widget.chatUserName] = _userMessages;
      _controller.clear();
    });

    // Simulate async backend send delay and update message status
    await Future.delayed(Duration(seconds: 1));

    setState(() {
      int index = _userMessages.indexOf(newMessage);
      if (index != -1) {
        _userMessages[index] = newMessage.copyWith(status: MessageStatus.sent);
      }
    });

    // Simulate delivered & read status updates later if needed
    await Future.delayed(Duration(seconds: 2));
    setState(() {
      int index = _userMessages.indexOf(newMessage);
      if (index != -1) {
        _userMessages[index] = newMessage.copyWith(status: MessageStatus.delivered);
      }
    });

    await Future.delayed(Duration(seconds: 2));
    setState(() {
      int index = _userMessages.indexOf(newMessage);
      if (index != -1) {
        _userMessages[index] = newMessage.copyWith(status: MessageStatus.read);
      }
    });
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.access_time, size: 16, color: Colors.grey);
      case MessageStatus.sent:
        return Icon(Icons.check, size: 16, color: Colors.grey);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 16, color: Colors.grey);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 16, color: Colors.blue);
      default:
        return SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HomePage()));
          },
        ),
        title: Text(widget.chatUserName),
        backgroundColor: Colors.teal.shade600,
      ),
      backgroundColor: Color(0xFFE5DDD5),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: EdgeInsets.all(8),
              itemCount: _userMessages.length,
              itemBuilder: (context, index) {
                final message = _userMessages[_userMessages.length - 1 - index];

                return Align(
                  alignment:
                  message.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: message.isSentByMe ? Colors.teal.shade400 : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: message.isSentByMe ? Radius.circular(12) : Radius.circular(0),
                        bottomRight: message.isSentByMe ? Radius.circular(0) : Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: message.isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.text,
                          style: TextStyle(
                            color: message.isSentByMe ? Colors.white : Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTimestamp(message.timestamp),
                              style: TextStyle(
                                color: message.isSentByMe ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            if (message.isSentByMe) ...[
                              SizedBox(width: 4),
                              _buildStatusIcon(message.status),
                            ]
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        fillColor: Colors.blueGrey[200],
                        filled: true,
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.teal.shade600,
                    child: IconButton(
                      icon: Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
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

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    if (now.difference(ts).inDays == 0) {
      return "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";
    } else {
      return "${ts.day}/${ts.month}/${ts.year}";
    }
  }
}

class ChatMessage {
  final String text;
  final bool isSentByMe;
  final DateTime timestamp;
  final MessageStatus status;

  ChatMessage({
    required this.text,
    required this.isSentByMe,
    required this.timestamp,
    this.status = MessageStatus.sent,
  });

  ChatMessage copyWith({
    String? text,
    bool? isSentByMe,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }
}
