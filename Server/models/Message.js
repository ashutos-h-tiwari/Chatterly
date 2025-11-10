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
    text: {
      type: String,
      trim: true,
      default: "",
    },
    attachments: [
      {
        type: String, // URLs or file paths
        trim: true,
      },
    ],
    readBy: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    deliveredTo: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
    isDeleted: {
      type: Boolean,
      default: false,
    },

    // ✅ NEW: temporary client-side id for idempotency & optimistic UI replacement
    clientId: {
      type: String,
      default: null,
      index: true,
      sparse: true,
    },
  },
  { timestamps: true }
);

/** 🔍 Useful indexes */
messageSchema.index({ conversationId: 1, createdAt: 1 }); // chronological fetch
messageSchema.index(
  { conversationId: 1, clientId: 1 },
  { unique: true, sparse: true }
); // prevent duplicate inserts on retries

export default mongoose.model("Message", messageSchema);
