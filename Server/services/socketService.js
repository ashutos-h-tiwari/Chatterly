import Message from "../models/Message.js";
import Conversation from "../models/Conversation.js";

export const createMessageAndBroadcast = async (io, payload) => {
  console.log("🧩 Received payload:", payload);

  const { conversationId, senderId, cipherText, contentType, text, clientId, attachments } = payload;

  if (!conversationId) {
    console.error("❌ Missing conversationId in payload");
    return;
  }
  if (!senderId) {
    console.error("❌ Missing senderId in payload");
    return;
  }

  // ✅ E2EE-first: never persist plaintext once cipherText is present
  const message = new Message({
    conversationId,
    sender: senderId,
    cipherText: cipherText || null,
    contentType: cipherText ? (contentType || "signal:whisper") : "legacy:plaintext",
    text: cipherText ? undefined : (text || ""),
    clientId: clientId || null,
    attachments: attachments || [],
  });

  await message.save();

  // update conversation lastMessage
  await Conversation.findByIdAndUpdate(
    conversationId,
    { lastMessage: message._id, updatedAt: new Date() }
  );

  // populate message for broadcast
  const populated =
    (message.populate && (await message.populate("sender", "name email avatar"))) ||
    (await Message.findById(message._id).populate("sender", "name email avatar"));

  // ✅ Build the wire payload explicitly — NEVER leak plaintext if cipherText exists
  const broadcastPayload = {
    _id: message._id,
    conversationId,
    cipherText: message.cipherText || null,
    contentType: message.contentType,
    text: message.cipherText ? undefined : (message.text || ""), // legacy only
    sender: populated?.sender
      ? {
          _id: populated.sender._id,
          name: populated.sender.name,
          email: populated.sender.email,
          avatar: populated.sender.avatar,
        }
      : { _id: senderId },
    attachments: message.attachments || [],
    clientId: message.clientId || null,
    createdAt: message.createdAt,
    status: "sent",
  };

  // emit to conversation room
  io.to(conversationId.toString()).emit("message:new", broadcastPayload);

  // emit to each participant personal room
  const conv = await Conversation.findById(conversationId).populate("participants", "_id");
  if (conv) {
    for (const p of conv.participants) {
      io.to(String(p._id)).emit("notification:new_message", { conversationId, message: broadcastPayload });
    }
  }

  console.log("📤 Message broadcasted to conversation:", conversationId);
};