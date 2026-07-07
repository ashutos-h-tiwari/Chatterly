import Message from "../models/Message.js";
import Conversation from "../models/Conversation.js";

export const createMessageAndBroadcast = async (io, payload) => {
  console.log("🧩 Received payload:", payload);

<<<<<<< HEAD
  const { conversationId, senderId, text, cipherText, contentType, attachments } = payload;

=======
// AFTER:
const { conversationId, senderId, cipherText, contentType, text, clientId, attachments } = payload;
>>>>>>> 37751586aba6bb6b8af6f403d2aabf6fcffb5386
  if (!conversationId) {
    console.error("❌ Missing conversationId in payload");
    return;
  }

  // ✅ Use conversationId if that’s your schema field
<<<<<<< HEAD
  const message = new Message({
    conversationId,
    sender: senderId,
    cipherText: cipherText || null,
    contentType: cipherText ? contentType || 'signal:whisper' : undefined,
    text: cipherText ? undefined : text || "",
    attachments: attachments || []
  });
=======
const message = new Message({
  conversationId,
  sender:      senderId,
  cipherText:  cipherText  || null,
  contentType: cipherText ? (contentType || "signal:whisper") : "legacy:plaintext",
  text:        cipherText ? undefined : (text || ""),
  clientId:    clientId   || null,
  attachments: attachments || [],
});
>>>>>>> 37751586aba6bb6b8af6f403d2aabf6fcffb5386

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

  // emit to conversation room
  io.to(conversationId).emit("message:new", broadcastPayload);
  // emit to each participant personal room
  const conv = await Conversation.findById(conversationId).populate("participants", "_id");
  for (const p of conv.participants) {
    io.to(String(p._id)).emit("notification:new_message", { conversationId, message: populated });
  }

  console.log("📤 Message broadcasted to conversation:", conversationId);
};
