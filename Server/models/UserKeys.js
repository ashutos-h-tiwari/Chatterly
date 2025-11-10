import mongoose from "mongoose";

const PreKeySchema = new mongoose.Schema(
  {
    keyId: { type: Number, required: true },
    publicKey: { type: String, required: true }, // base64
    isUsed: { type: Boolean, default: false },
  },
  { _id: false }
);

const userKeysSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: "User", unique: true, required: true },

    identityKey: { type: String, required: true },            // base64 public
    signedPreKeyId: { type: Number, required: true },
    signedPreKeyPublic: { type: String, required: true },     // base64 public
    signedPreKeySignature: { type: String, required: true },  // base64

    oneTimePreKeys: [PreKeySchema],
    updatedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

userKeysSchema.index({ user: 1 }, { unique: true });

export default mongoose.model("UserKeys", userKeysSchema);
