import mongoose from "mongoose";

const conversationSchema = new mongoose.Schema(
  {
    participants: [{ type: mongoose.Schema.Types.ObjectId, ref: "User", required: true }],
    lastMessage: { type: mongoose.Schema.Types.ObjectId, ref: "Message" },

    // For 1-1 chats: deterministic unique key "A:B"
    pairKey: { type: String, unique: true, sparse: true, index: true },
  },
  { timestamps: true }
);

conversationSchema.index({ participants: 1 });
conversationSchema.index({ updatedAt: -1 });

conversationSchema.pre("save", function (next) {
  if (!this.pairKey && Array.isArray(this.participants) && this.participants.length === 2) {
    const sorted = this.participants.map(String).sort();
    this.pairKey = `${sorted[0]}:${sorted[1]}`;
  }
  next();
});

export default mongoose.model("Conversation", conversationSchema);
