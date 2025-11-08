import Message from "../models/Message.js";
import Conversation from "../models/Conversation.js";

export const createMessageAndBroadcast = async (io, payload) => {
  console.log("🧩 Received payload:", payload);

  const { conversationId, senderId, text, attachments } = payload;

  if (!conversationId) {
    console.error("❌ Missing conversationId in payload");
    return;
  }

  // ✅ Use conversationId if that’s your schema field
  const message = new Message({
    conversationId,
    sender: senderId,
    text: text || "",
    attachments: attachments || []
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

  // emit to conversation room
  io.to(conversationId).emit("message:receive", populated);

  // emit to each participant personal room
  const conv = await Conversation.findById(conversationId).populate("participants", "_id");
  for (const p of conv.participants) {
    io.to(String(p._id)).emit("notification:new_message", { conversationId, message: populated });
  }

  console.log("📤 Message broadcasted to conversation:", conversationId);
};
