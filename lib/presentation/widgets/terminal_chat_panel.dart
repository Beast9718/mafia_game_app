import 'package:flutter/material.dart';

class TerminalChatPanel extends StatefulWidget {
  final String channel;
  final Color themeColor;
  final bool isDisabled;
  final List<Map<String, dynamic>> messages;
  final String myName;
  final Function(String) onSendMessage;

  const TerminalChatPanel({
    super.key,
    required this.channel,
    required this.themeColor,
    required this.isDisabled,
    required this.messages,
    required this.myName,
    required this.onSendMessage,
  });

  @override
  State<TerminalChatPanel> createState() => _TerminalChatPanelState();
}

class _TerminalChatPanelState extends State<TerminalChatPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll on initial load
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant TerminalChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _submitMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.onSendMessage(text);
    _textController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final isMafia = widget.channel == "mafia";
    final label = isMafia 
        ? "SECURED MAFIA COM-LINK [REDLINE]" 
        : "PUBLIC DISCUSSION NETWORK [LOCAL_NET]";

    final Color panelBg = isMafia ? const Color(0xFF140203) : const Color(0xFF07090C);
    final Color borderCol = widget.themeColor.withValues(alpha: 0.3);
    final Color headerTextCol = widget.themeColor.withValues(alpha: 0.85);

    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border.all(color: borderCol, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: widget.themeColor.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 1,
          )
        ]
      ),
      child: Column(
        children: [
          // Console Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderCol, width: 1)),
              color: Colors.black26,
            ),
            child: Row(
              children: [
                // Glowing dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.themeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.themeColor,
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: headerTextCol,
                    fontSize: 9,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  "STATUS: ONLINE",
                  style: TextStyle(
                    color: widget.themeColor.withValues(alpha: 0.6),
                    fontSize: 8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Message log
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.messages.isEmpty ? 1 : widget.messages.length,
                itemBuilder: (context, index) {
                  if (widget.messages.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        isMafia 
                            ? "> COORDINATE TARGET ATTACKS. VOICE TRANSMISSION SECURED."
                            : "> ESTABLISHED NETWORK CONNECTION. DISCUSS SUSPECT LOGS.",
                        style: TextStyle(
                          color: widget.themeColor.withValues(alpha: 0.35),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  }

                  final msg = widget.messages[index];
                  final String sender = msg["sender"] ?? "Unknown";
                  final String text = msg["message"] ?? "";
                  final bool isMe = sender == widget.myName;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: isMe ? "[YOU]: " : "[${sender.toUpperCase()}]: ",
                            style: TextStyle(
                              color: isMe 
                                  ? widget.themeColor 
                                  : (isMafia ? Colors.redAccent.shade100 : Colors.white60),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          TextSpan(
                            text: text,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Input Block
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderCol, width: 1)),
              color: Colors.black38,
            ),
            child: widget.isDisabled
                ? SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        isMafia 
                            ? "[ERROR: TRANSMITTER DISCONNECTED - YOU ARE DEAD]"
                            : "[ERROR: NETWORK BLOCKED - YOU ARE DEAD]",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Text(
                        "> ",
                        style: TextStyle(
                          color: widget.themeColor,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          cursorColor: widget.themeColor,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            hintText: isMafia ? "Coordinate kill target..." : "Discuss alignments...",
                            hintStyle: TextStyle(
                              color: widget.themeColor.withValues(alpha: 0.3),
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (_) => _submitMessage(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send_rounded, size: 16, color: widget.themeColor),
                        onPressed: _submitMessage,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
