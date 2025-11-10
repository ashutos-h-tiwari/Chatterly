import express from "express";
import { auth } from "../middlewares/authMiddleware.js";
import upload from "../middlewares/upload.js";

import {
  createOrGetConversation,
  getConversations,
  getMessages,
  sendMessage,
} from "../controllers/chatController.js";

const router = express.Router();

// ✅ All routes require authentication
router.use(auth);

/* ---------------------------------------------------
   🗨️ Conversations
--------------------------------------------------- */

// ✅ Create or Get 1-on-1 Conversation (idempotent, upsert)
router.post("/conversations", createOrGetConversation);

// ✅ Get all user conversations (sorted by updatedAt desc)
router.get("/conversations", getConversations);

/* ---------------------------------------------------
   💬 Messages
--------------------------------------------------- */

// ✅ Get all messages of a conversation
router.get("/conversations/:conversationId/messages", getMessages);

// ✅ Send a new message (text + optional Cloudinary upload)
router.post(
  "/conversations/:conversationId/messages",
  upload.single("attachment"), // optional file
  sendMessage
);

export default router;
