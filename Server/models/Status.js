import mongoose from "mongoose";

const statusSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "User",
    required: true,
  },
  mediaUrl: {
    type: String, // Cloudinary URL
    required: true,
  },
  mediaType: {
    type: String, // "image", "video", "audio"
    enum: ["image", "video", "audio"],
    required: true,
  },
  caption: {
    type: String,
    default: "",
  },
  viewers: [
    {
      userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
      viewedAt: {
        type: Date,
        default: Date.now,
      },
    },
  ],
  createdAt: {
    type: Date,
    default: Date.now,
    // Auto-delete after 24 hours (TTL index)
    expires: 86400, // 24 hours in seconds
  },
}, { timestamps: true });

// ✅ TTL index to auto-delete statuses after 24 hours
statusSchema.index({ createdAt: 1 }, { expireAfterSeconds: 86400 });

export default mongoose.model("Status", statusSchema);
