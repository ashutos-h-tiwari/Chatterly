import mongoose from "mongoose";

const userSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true },
  name: { type: String },
  avatar: { type: String },         // URL or uploaded filename
  socketId: { type: String, default: null }, // current socket id for presence
  isOnline: { type: Boolean, default: false }
}, { timestamps: true });

export default mongoose.model("User", userSchema);
