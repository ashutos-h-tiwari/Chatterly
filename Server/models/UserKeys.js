import mongoose from "mongoose";

const PreKeySchema = new mongoose.Schema(
  {
    keyId:     { type: Number, required: true },
    publicKey: { type: String, required: true }, // base64
    isUsed:    { type: Boolean, default: false },
  },
  { _id: false }
);

const userKeysSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      unique: true,
      required: true,
    },

<<<<<<< HEAD
    identityKey: { type: String, required: true },            // base64 public
      identitySigningKey: { type: String, required: false },   // base64 Ed25519 public (optional)
    signedPreKeyId: { type: Number, required: true },
    signedPreKeyPublic: { type: String, required: true },     // base64 public
    signedPreKeySignature: { type: String, required: true },  // base64
=======
    // ── Signal Protocol fields ───────────────────────────────────────────
    registrationId:        { type: Number },          // ADD: required by libsignal

    identityKey:           { type: String, required: true },   // base64 public
    signedPreKeyId:        { type: Number, required: true },
    signedPreKeyPublic:    { type: String, required: true },   // base64 public
    signedPreKeySignature: { type: String, required: true },   // base64
>>>>>>> 37751586aba6bb6b8af6f403d2aabf6fcffb5386

    oneTimePreKeys: [PreKeySchema],

    // ── Tracking ─────────────────────────────────────────────────────────
    keysUploadedAt: { type: Date, default: Date.now }, // ADD: useful for key rotation
  },
  { timestamps: true }
);

userKeysSchema.index({ user: 1 }, { unique: true });

export default mongoose.model("UserKeys", userKeysSchema);