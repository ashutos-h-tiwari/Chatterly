import Conversation from "../models/Conversation.js";
import Message from "../models/Message.js";
import User from "../models/User.js";

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
      conversation = await conversation.populate("participants", "name email avatar");
    }

    res.status(200).json(conversation);
  } catch (err) {
    console.error("❌ Error in createOrGetConversation:", err.message);
    res.status(500).json({ error: "Failed to create or get conversation" });
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

    res.status(200).json(conversations);
  } catch (err) {
    console.error("❌ Error in getConversations:", err.message);
    res.status(500).json({ error: "Failed to fetch conversations" });
  }
};

// ✅ Get all messages in a conversation
export const getMessages = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const messages = await Message.find({ conversationId })
      .populate("sender", "name email avatar")
      .sort({ createdAt: 1 });
    res.status(200).json(messages);
  } catch (err) {
    console.error("❌ Error in getMessages:", err.message);
    res.status(500).json({ error: "Failed to fetch messages" });
  }
};

// ✅ Send message (text + optional Cloudinary attachment)
export const sendMessage = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { text } = req.body;

    if (!conversationId)
      return res.status(400).json({ message: "Conversation ID is required" });

    if (!text && !req.file)
      return res.status(400).json({ message: "Text or attachment is required" });

    const attachmentUrl = req.file ? req.file.path : null; // Cloudinary URL from multer

    const newMessage = await Message.create({
      conversationId,
      sender: req.user._id,
      text,
      attachments: attachmentUrl ? [attachmentUrl] : [],
    });

    await Conversation.findByIdAndUpdate(conversationId, {
      lastMessage: newMessage._id,
      updatedAt: new Date(),
    });

    const populatedMessage = await Message.findById(newMessage._id)
      .populate("sender", "name email avatar");

    res.status(201).json({
      success: true,
      message: "Message sent successfully",
      data: populatedMessage,
    });
  } catch (error) {
    console.error("❌ Error in sendMessage:", error);
    res.status(500).json({
      success: false,
      message: "Failed to send message",
      error: error.message,
    });
  }
};
