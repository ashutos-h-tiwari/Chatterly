import mongoose from "mongoose";

const messageSchema = new mongoose.Schema(
  {
    conversationId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Conversation",
      required: [true, "Conversation ID is required"],
      index: true,
    },
    sender: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: [true, "Sender is required"],
      index: true,
    },

    // E2EE fields
    cipherText: { type: String, index: true },                 // base64 signal message
    contentType: { type: String, default: "signal:whisper" }, // 'signal:prekey' | 'signal:whisper' | 'signal:attachment'

    // Legacy/plaintext (only during migration; avoid storing long-term)
    text: { type: String, trim: true, default: "" },

    attachments: [{ type: String, trim: true }], // if you still need array of URLs
    readBy: [{ type: mongoose.Schema.Types.ObjectId, ref: "User" }],
    deliveredTo: [{ type: mongoose.Schema.Types.ObjectId, ref: "User" }],
    isDeleted: { type: Boolean, default: false },

    // Optimistic UI / Idempotency
    clientId: { type: String, index: true, sparse: true },

    // Optional envelope for file encryption (if you implement AES-GCM per file)
    attachmentUrl: { type: String },
    attachmentSize: { type: Number },
    attachmentNonce: { type: String },
    attachmentTag: { type: String },
  },
  { timestamps: true }
);

messageSchema.index({ conversationId: 1, createdAt: 1 });
messageSchema.index({ conversationId: 1, clientId: 1 }, { unique: true, sparse: true });

export default mongoose.model("Message", messageSchema);
