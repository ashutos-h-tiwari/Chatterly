// socket-test.js
import { io } from "socket.io-client";

const SERVER = "http://localhost:5000";
const TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY5MGQ5NGNiNzVhYjUwMzY5YTkyOWVlOCIsImlhdCI6MTc2MjUyNjAwMywiZXhwIjoxNzYzMTMwODAzfQ.0upIvbaSGaaARTnUXmT2FhyhCvi_GmNUTHM1voCTQnM";   // 🔒 Paste JWT from /api/auth/login
const USER_ID = "690d94cb75ab50369a929ee8"; // 🧍 Paste Alice’s MongoDB _id
const CONVO_ID = "690df19df73cfe79d069d2bd"; // 💬 Conversation ID

// Connect to Socket.IO
const socket = io(SERVER, {
  auth: { token: TOKEN },
  transports: ["websocket"],
});

socket.on("connect", () => {
  console.log("✅ Connected:", socket.id);
  socket.emit("user:connect", { userId: USER_ID });
  socket.emit("join:conversation", { conversationId: CONVO_ID });

  // Wait 2 seconds before sending the message
  setTimeout(() => {
    socket.emit("message:send", {
      conversationId: CONVO_ID,
      senderId: USER_ID,
      text: "Hello from Alice! 👋",
      attachments: [],
    });
  }, 2000);
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
