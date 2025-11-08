import express from "express";
import { auth } from "../middlewares/authMiddleware.js";
import upload from "../middlewares/upload.js"; // ✅ Cloudinary upload middleware
import {
  createOrGetConversation,
  getConversations,
  getMessages,
  sendMessage,
} from "../controllers/chatController.js";

const router = express.Router();

// ✅ All routes require authentication
router.use(auth);

// ✅ Create or get conversation
router.post("/conversation", createOrGetConversation);

// ✅ Get all user conversations
router.get("/conversations", getConversations);

// ✅ Get all messages for a specific conversation
router.get("/conversations/:conversationId/messages", getMessages);

// ✅ Send new message (text + optional Cloudinary file)
router.post(
  "/conversations/:conversationId/messages",
  upload.single("attachment"),
  sendMessage
);

export default router;
