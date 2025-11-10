import jwt from "jsonwebtoken";

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

      // Personal room (optional presence)
      socket.join(socket.userId);
      socket.broadcast.emit("user:online", { userId: socket.userId });

      socket.joinedConversations = new Set();

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
      // Back-compat aliases
      socket.on("join", joinHandler);
      socket.on("leave", leaveHandler);

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
