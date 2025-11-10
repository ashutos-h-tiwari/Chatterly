// controllers/chatController.js
import Conversation from "../models/Conversation.js";
import Message from "../models/Message.js";
import { emitMessageToRoom } from "../utils/socketUtils.js";

/**
 * Create or Get a 1-1 Conversation (atomic, race-safe via pairKey)
 */
export const createOrGetConversation = async (req, res) => {
  try {
    const { participantId } = req.body;
    if (!participantId)
      return res.status(400).json({ message: "participantId is required" });

    const a = req.user._id.toString();
    const b = participantId.toString();
    const [u1, u2] = [a, b].sort();
    const pairKey = `${u1}:${u2}`;

    const convo = await Conversation.findOneAndUpdate(
      { pairKey },
      { $setOnInsert: { participants: [u1, u2], pairKey } },
      { new: true, upsert: true }
    )
      .populate("participants", "name email avatar")
      .populate({
        path: "lastMessage",
        populate: { path: "sender", select: "name email avatar" },
      });

    return res.status(200).json(convo);
  } catch (err) {
    if (err?.code === 11000) {
      const again = await Conversation.findOne({ pairKey })
        .populate("participants", "name email avatar")
        .populate({
          path: "lastMessage",
          populate: { path: "sender", select: "name email avatar" },
        });
      return res.status(200).json(again);
    }
    console.error("❌ createOrGetConversation:", err);
    return res
      .status(500)
      .json({ error: "Failed to create or get conversation" });
  }
};

/**
 * Get all conversations for the user
 */
export const getConversations = async (req, res) => {
  try {
    const conversations = await Conversation.find({
      participants: req.user._id,
    })
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

/**
 * Get messages in a conversation
 * NOTE: For E2EE we return cipherText + contentType; client decrypts locally.
 */
export const getMessages = async (req, res) => {
  try {
    const { conversationId } = req.params;

    // authorize membership
    const exists = await Conversation.exists({
      _id: conversationId,
      participants: req.user._id,
    });
    if (!exists) {
      return res.status(403).json({ message: "Access denied to conversation" });
    }

    const messages = await Message.find({ conversationId })
      .select(
        "_id conversationId sender cipherText contentType text clientId attachments attachmentUrl attachmentSize attachmentNonce attachmentTag createdAt"
      )
      .populate("sender", "name email avatar")
      .sort({ createdAt: 1 });

    return res.status(200).json(messages);
  } catch (err) {
    console.error("❌ Error in getMessages:", err.message);
    return res.status(500).json({ error: "Failed to fetch messages" });
  }
};

/**
 * Send message (E2EE-first):
 * - Expect { cipherText, contentType, clientId }
 * - Optional legacy { text } during migration (not recommended long-term)
 * - Optional file via `upload.single('attachment')` which should be ALREADY encrypted client-side.
 */
export const sendMessage = async (req, res) => {
  try {
    const { conversationId } = req.params;

    // E2EE fields
    const { cipherText, contentType, clientId } = req.body;

    // Legacy plaintext (migration only)
    const plaintext = req.body.text;

    // Attachment (should be encrypted before upload)
    const attachmentUrl = req.file ? req.file.path : null;

    if (!cipherText && !plaintext && !attachmentUrl) {
      return res.status(400).json({
        success: false,
        message: "cipherText required (or legacy text / encrypted attachment)",
      });
    }

    // authorize membership
    const conv = await Conversation.findOne({
      _id: conversationId,
      participants: req.user._id,
    });
    if (!conv) {
      return res
        .status(403)
        .json({ success: false, message: "Access denied to conversation" });
    }

    // Persist
    const doc = await Message.create({
      conversationId,
      sender: req.user._id,
      cipherText: cipherText || null,
      contentType: cipherText
        ? contentType || "signal:whisper"
        : attachmentUrl
        ? "signal:attachment"
        : "legacy:plaintext",
      text: plaintext || undefined, // avoid storing long-term; only for transition
      clientId: clientId || null,
      attachments: attachmentUrl ? [attachmentUrl] : [],
    });

    await Conversation.findByIdAndUpdate(conversationId, {
      lastMessage: doc._id,
      updatedAt: new Date(),
    });

    // Payload for clients (NEVER include plaintext if cipherText exists)
    const payload = {
      _id: doc._id,
      cipherText: doc.cipherText || null,
      contentType: doc.contentType,
      text: doc.cipherText ? undefined : doc.text || "", // legacy only
      sender: { _id: req.user._id },
      attachments: doc.attachments || [],
      createdAt: doc.createdAt,
      conversationId,
      clientId: doc.clientId || null,
      status: "sent",
    };

    // Realtime broadcast
    emitMessageToRoom(conversationId, payload);

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
