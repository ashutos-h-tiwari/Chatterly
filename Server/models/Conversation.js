import mongoose from "mongoose";

const conversationSchema = new mongoose.Schema(
  {
    participants: [
      { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    ],
    lastMessage: { type: mongoose.Schema.Types.ObjectId, ref: "Message" },

    // NEW: for 1-1 chats — sorted participant IDs "A:B"
    pairKey: { type: String, unique: true, index: true, sparse: true },
  },
  { timestamps: true }
);

// Helpful indexes
conversationSchema.index({ participants: 1 });
conversationSchema.index({ updatedAt: -1 });

// Auto-fill pairKey when exactly two participants
conversationSchema.pre("save", function (next) {
  if (!this.pairKey && Array.isArray(this.participants) && this.participants.length === 2) {
    const sorted = this.participants.map(String).sort();
    this.pairKey = `${sorted[0]}:${sorted[1]}`;
  }
  next();
});

export default mongoose.model("Conversation", conversationSchema);
