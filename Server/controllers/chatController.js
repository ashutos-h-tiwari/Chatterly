// controllers/chatController.js
import Conversation from "../models/Conversation.js";
import Message from "../models/Message.js";
import User from "../models/User.js";
import { emitMessageToRoom } from "../utils/socketUtils.js";

// ✅ Create or Get a Conversation
export const createOrGetConversation = async (req, res) => {
  try {
    const { participantId } = req.body;
    if (!participantId)
      return res.status(400).json({ message: "participantId is required" });

    let conversation = await Conversation.findOne({
      participants: { $all: [req.user._id, participantId] },
    })
      .populate("participants", "name email avatar")
      .populate({
        path: "lastMessage",
        populate: { path: "sender", select: "name email avatar" },
      });

    if (!conversation) {
      conversation = new Conversation({
        participants: [req.user._id, participantId],
      });
      await conversation.save();
      conversation = await conversation.populate(
        "participants",
        "name email avatar"
      );
    }

    return res.status(200).json(conversation);
  } catch (err) {
    console.error("❌ Error in createOrGetConversation:", err.message);
    return res.status(500).json({ error: "Failed to create or get conversation" });
  }
};

// ✅ Get all conversations
export const getConversations = async (req, res) => {
  try {
    const conversations = await Conversation.find({ participants: req.user._id })
      .populate("participants", "name email avatar")
      .populate({
        path: "lastMessage",
        populate: { path: "sender", select: "name email avatar" },
      })
      .sort({ updatedAt: -1 });

    return res.status(200).json(conversations);
  } catch (err) {
    console.error("❌ Error in getConversations:", err.message);
    return res.status(500).json({ error: "Failed to fetch conversations" });
  }
};

// ✅ Get all messages in a conversation
export const getMessages = async (req, res) => {
  try {
    const { conversationId } = req.params;

    // Optional: authorize that user is in this conversation
    const exists = await Conversation.exists({
      _id: conversationId,
      participants: req.user._id,
    });
    if (!exists) {
      return res.status(403).json({ message: "Access denied to conversation" });
    }

    const messages = await Message.find({ conversationId })
      .populate("sender", "name email avatar")
      .sort({ createdAt: 1 });

    return res.status(200).json(messages);
  } catch (err) {
    console.error("❌ Error in getMessages:", err.message);
    return res.status(500).json({ error: "Failed to fetch messages" });
  }
};

// ✅ Send message (HTTP) — now also broadcasts to Socket.IO room
export const sendMessage = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { text, clientId } = req.body; // clientId from app (tempId)
    if (!conversationId)
      return res.status(400).json({ message: "Conversation ID is required" });
    if (!text && !req.file)
      return res.status(400).json({ message: "Text or attachment is required" });

    // authorize membership
    const conv = await Conversation.findOne({
      _id: conversationId,
      participants: req.user._id,
    });
    if (!conv) {
      return res.status(403).json({ message: "Access denied to conversation" });
    }

    const attachmentUrl = req.file ? req.file.path : null;

    // 1) persist
    const newMessage = await Message.create({
      conversationId,
      sender: req.user._id,
      text,
      attachments: attachmentUrl ? [attachmentUrl] : [],
      clientId: clientId || null, // <-- add this field in Message schema (String, index optional)
    });

    // 2) update conversation metadata
    await Conversation.findByIdAndUpdate(conversationId, {
      lastMessage: newMessage._id,
      updatedAt: new Date(),
    });

    // 3) shape payload for clients
    const populatedMessage = await Message.findById(newMessage._id)
      .populate("sender", "name email avatar");

    const payload = {
      _id: populatedMessage._id,
      text: populatedMessage.text || "",
      sender: populatedMessage.sender, // {_id, name, ...}
      attachments: populatedMessage.attachments || [],
      createdAt: populatedMessage.createdAt,
      conversationId,
      clientId: populatedMessage.clientId || null,
      status: "sent",
    };

    // 4) realtime broadcast to room (so both users see instantly)
    emitMessageToRoom(conversationId, payload);

    // 5) HTTP response
    return res.status(201).json({
      success: true,
      message: "Message sent successfully",
      data: payload,
    });
  } catch (error) {
    console.error("❌ Error in sendMessage:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to send message",
      error: error.message,
    });
  }
};
