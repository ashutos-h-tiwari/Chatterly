// utils/socketUtils.js
import jwt from "jsonwebtoken";

let ioRef = null;
export const getIO = () => ioRef;

export const initSocket = (io) => {
  ioRef = io;

  io.on("connection", async (socket) => {
    try {
      // ✅ accept token from both auth and query (Flutter sends query)
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.query?.token ||
        null;

      if (!token) {
        console.warn("❌ No token provided, disconnecting");
        return socket.disconnect(true);
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.id;
      console.log(`✅ Socket connected: ${socket.id} | User: ${socket.userId}`);

      // Join a personal room (optional presence/DMs)
      socket.join(socket.userId);
      socket.broadcast.emit("user:online", { userId: socket.userId });

      // Track joined conversations
      socket.joinedConversations = new Set();

      // ✅ Support BOTH event names for compatibility
      const joinHandler = ({ conversationId, roomId }) => {
        const convId = conversationId || roomId;
        if (!convId) return;
        socket.join(convId);
        socket.joinedConversations.add(convId);
        console.log(`🟢 User ${socket.userId} joined conversation ${convId}`);
      };

      const leaveHandler = ({ conversationId, roomId }) => {
        const convId = conversationId || roomId;
        if (!convId) return;
        socket.leave(convId);
        socket.joinedConversations.delete(convId);
        console.log(`🔴 User ${socket.userId} left conversation ${convId}`);
      };

      socket.on("join:conversation", joinHandler);
      socket.on("leave:conversation", leaveHandler);

      // Backward-compat aliases (Flutter was emitting 'join')
      socket.on("join", joinHandler);
      socket.on("leave", leaveHandler);

      // If client chooses to send via socket (optional)
      socket.on("message:send", async (payload) => {
        try {
          const { conversationId } = payload || {};
          if (!conversationId) {
            return socket.emit("message:error", { message: "conversationId missing" });
          }
          if (!socket.joinedConversations.has(conversationId)) {
            console.warn(
              `⚠️ User ${socket.userId} sending to ${conversationId} before join — auto-joining`
            );
            socket.join(conversationId);
            socket.joinedConversations.add(conversationId);
          }

          const { createMessageAndBroadcast } = await import("../services/socketService.js");
          await createMessageAndBroadcast(io, {
            ...payload,
            senderId: socket.userId, // trust server auth
          });

          console.log(`📤 Socket message broadcasted to conversation ${conversationId}`);
        } catch (err) {
          console.error("❌ message:send error:", err.message);
          socket.emit("message:error", { message: "Failed to send message" });
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

/**
 * Helper: broadcast a message to a conversation room
 */
export function emitMessageToRoom(conversationId, payload) {
  if (!ioRef || !conversationId) return;
  ioRef.to(conversationId.toString()).emit("message:new", payload);
}
