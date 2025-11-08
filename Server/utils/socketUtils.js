import jwt from "jsonwebtoken";

export const initSocket = (io) => {
  io.on("connection", async (socket) => {
    try {
      const token = socket.handshake.auth?.token;
      if (!token) {
        console.warn("❌ No token provided, disconnecting");
        return socket.disconnect(true);
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.id;
      console.log(`✅ Socket connected: ${socket.id} | User: ${socket.userId}`);

      // Join personal room
      socket.join(socket.userId);

      socket.broadcast.emit("user:online", { userId: socket.userId });

      // ✅ Track which conversations user has joined
      socket.joinedConversations = new Set();

      socket.on("join:conversation", ({ conversationId }) => {
        socket.join(conversationId);
        socket.joinedConversations.add(conversationId);
        console.log(`🟢 User ${socket.userId} joined conversation ${conversationId}`);
      });

      socket.on("leave:conversation", ({ conversationId }) => {
        socket.leave(conversationId);
        socket.joinedConversations.delete(conversationId);
        console.log(`🔴 User ${socket.userId} left conversation ${conversationId}`);
      });

      socket.on("message:send", async (payload) => {
        try {
          const { conversationId, senderId } = payload;

          if (!socket.joinedConversations.has(conversationId)) {
            console.warn(`⚠️ User ${senderId} tried to send to convo ${conversationId} before joining`);
            socket.join(conversationId); // auto-join fallback
          }

          const { createMessageAndBroadcast } = await import("../services/socketService.js");
          await createMessageAndBroadcast(io, payload);
          console.log(`📤 Message broadcasted to conversation ${conversationId}`);

        } catch (err) {
          console.error("❌ Message send error:", err.message);
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
