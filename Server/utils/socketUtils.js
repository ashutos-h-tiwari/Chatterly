// utils/socketUtils.js
import jwt from "jsonwebtoken";
import Message from "../models/Message.js";              // 👈 needed for receipts
// (Optional) import Conversation if you plan to validate membership
// import Conversation from "../models/Conversation.js";

let ioRef = null;
export const getIO = () => ioRef;

export const initSocket = (io) => {
  ioRef = io;

  io.on("connection", async (socket) => {
    try {
      // Accept token from query or auth
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) {
        console.warn("❌ No token provided, disconnecting");
        return socket.disconnect(true);
      }
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.id;
      console.log(`✅ Socket connected: ${socket.id} | User: ${socket.userId}`);

      // Presence (optional)
      socket.join(socket.userId);
      socket.broadcast.emit("user:online", { userId: socket.userId });

      socket.joinedConversations = new Set();

      const joinHandler = ({ conversationId, roomId }) => {
        const convId = (conversationId || roomId || "").toString();
        if (!convId) return;
        socket.join(convId);
        socket.joinedConversations.add(convId);
        console.log(`🟢 User ${socket.userId} joined conversation ${convId}`);
      };
      const leaveHandler = ({ conversationId, roomId }) => {
        const convId = (conversationId || roomId || "").toString();
        if (!convId) return;
        socket.leave(convId);
        socket.joinedConversations.delete(convId);
        console.log(`🔴 User ${socket.userId} left conversation ${convId}`);
      };

      socket.on("join:conversation", joinHandler);
      socket.on("leave:conversation", leaveHandler);
      // Back-compat aliases
      socket.on("join", joinHandler);
      socket.on("leave", leaveHandler);

      /* -------------------------------------------------------
         📬 DELIVERY RECEIPT: flip ✓ → ✓✓ (gray)
         Client emits: { conversationId, messageId }
      ------------------------------------------------------- */
      socket.on("message:delivered", async ({ conversationId, messageId }) => {
        try {
          if (!conversationId || !messageId) return;
          await Message.findByIdAndUpdate(
            messageId,
            { $addToSet: { deliveredTo: socket.userId } },
            { new: false }
          );
          io.to(conversationId.toString()).emit("message:status", {
            _id: messageId,
            messageId,
            status: "delivered",
          });
        } catch (e) {
          console.error("message:delivered error:", e.message);
        }
      });

      /* -------------------------------------------------------
         👁 READ RECEIPT: flip ✓✓ gray → ✓✓ blue
         Client emits: { conversationId, messageId }
      ------------------------------------------------------- */
      socket.on("message:read", async ({ conversationId, messageId }) => {
        try {
          if (!conversationId || !messageId) return;
          await Message.findByIdAndUpdate(
            messageId,
            { $addToSet: { readBy: socket.userId } },
            { new: false }
          );
          io.to(conversationId.toString()).emit("message:status", {
            _id: messageId,
            messageId,
            status: "read",
          });
        } catch (e) {
          console.error("message:read error:", e.message);
        }
      });

      /* -------------------------------------------------------
         (Optional) Mark all visible as read when opening chat
         Client emits: { conversationId }
      ------------------------------------------------------- */
      socket.on("messages:markRead", async ({ conversationId }) => {
        try {
          if (!conversationId) return;
          const ids = await Message.find({
            conversationId,
            sender: { $ne: socket.userId },
            readBy: { $ne: socket.userId },
          }).distinct("_id");

          if (!ids.length) return;

          await Message.updateMany(
            { _id: { $in: ids } },
            { $addToSet: { readBy: socket.userId } }
          );

          ids.forEach((id) => {
            io.to(conversationId.toString()).emit("message:status", {
              _id: id,
              messageId: id,
              status: "read",
            });
          });
        } catch (e) {
          console.error("messages:markRead error:", e.message);
        }
      });

      socket.on("disconnect", () => {
        console.log(`❌ Socket disconnected: ${socket.id} | User: ${socket.userId}`);
        socket.broadcast.emit("user:offline", { userId: socket.userId });
      });
    } catch (err) {
      console.error("Socket auth error:", err.message);
      socket.disconnect(true);
    }
  });
};

export function emitMessageToRoom(conversationId, payload) {
  if (!ioRef || !conversationId) return;
  ioRef.to(conversationId.toString()).emit("message:new", payload);
}
