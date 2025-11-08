// socket-test.js
import { io } from "socket.io-client";

const SERVER = "http://localhost:5000";
const TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY5MGRhYjZjYWU4ZDA2YjFhZjBhYTY3OCIsImlhdCI6MTc2MjUyNDk4OSwiZXhwIjoxNzYzMTI5Nzg5fQ.7pEjWVEhBpmB5baC8zu-jGgkL-EPvL2dbX-ERvjg8Ts";   // 🔒 Paste JWT from /api/auth/login
const USER_ID = "690dab6cae8d06b1af0aa678"; // 🧍 Paste BOB MongoDB _id
const CONVO_ID = "690df19df73cfe79d069d2bd"; // 💬 Conversation ID

// Connect to Socket.IO
const socket = io(SERVER, {
  auth: { token: TOKEN },
  transports: ["websocket"],
});

socket.on("connect", () => {
  console.log("✅ Connected:", socket.id);

  // Identify user to server
  socket.emit("user:connect", { userId: USER_ID });

  // Join specific conversation room
  socket.emit("join:conversation", { conversationId: CONVO_ID });

  // Send a message
  socket.emit("message:send", {
    conversationId: CONVO_ID,
    senderId: USER_ID,
    text: "Hello from Alice! 👋",
    attachments: [],
  });
});

// When a message is received
socket.on("message:receive", (msg) => {
  console.log("📩 message:receive", msg);
});

// Optional: message notification
socket.on("notification:new_message", (payload) => {
  console.log("🔔 notification", payload);
});

// Error and disconnect handling
socket.on("disconnect", () => console.log("❌ Disconnected"));
socket.on("connect_error", (err) => console.error("⚠️ Connect error:", err.message));
