import express from "express";
import { auth } from "../middlewares/authMiddleware.js";
import UserKeys from "../models/UserKeys.js";
import nacl from 'tweetnacl';

function verifySignature(publicBase64, messageBase64, signatureBase64) {
  try {
    const pub = Buffer.from(publicBase64, 'base64');
    const msg = Buffer.from(messageBase64, 'base64');
    const sig = Buffer.from(signatureBase64, 'base64');
    return nacl.sign.detached.verify(new Uint8Array(msg), new Uint8Array(sig), new Uint8Array(pub));
  } catch (e) {
    return false;
  }
}

const router = express.Router();
router.use(auth);

// Upload or refresh my public key bundle
router.post("/upload", async (req, res) => {
  try {
    const {
      identityKey,
      identitySigningPublic,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      oneTimePreKeys, // [{ keyId, publicKey }]
    } = req.body;

    if (!identityKey || !signedPreKeyId || !signedPreKeyPublic || !signedPreKeySignature || !identitySigningPublic) {
      return res.status(400).json({ success: false, message: "Missing key material (require identitySigningPublic)" });
    }

    // verify signature of signedPreKeyPublic using provided identitySigningPublic
    const ok = verifySignature(identitySigningPublic, signedPreKeyPublic, signedPreKeySignature);
    if (!ok) {
      return res.status(400).json({ success: false, message: 'signedPreKeySignature invalid' });
    }

    const update = {
      identityKey,
      identitySigningKey: identitySigningPublic,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      updatedAt: new Date(),
    };
    if (Array.isArray(oneTimePreKeys)) update.oneTimePreKeys = oneTimePreKeys;

    await UserKeys.findOneAndUpdate(
      { user: req.user._id },
      { $set: update },
      { new: true, upsert: true }
    );

    return res.json({ success: true });
  } catch (e) {
    console.error("keys/upload error:", e);
    return res.status(500).json({ success: false, message: "Key upload failed" });
  }
});

// Fetch recipient’s bundle (reserves one one-time prekey if available)
router.post("/bundle", async (req, res) => {
  try {
    const { recipientId } = req.body;
    if (!recipientId) return res.status(400).json({ success: false, message: "recipientId required" });

    const keys = await UserKeys.findOne({ user: recipientId });
    if (!keys) return res.status(404).json({ success: false, message: "No bundle for user" });

    let oneTimePreKey = null;
    const idx = (keys.oneTimePreKeys || []).findIndex((k) => !k.isUsed);
    if (idx >= 0) {
      oneTimePreKey = {
        keyId: keys.oneTimePreKeys[idx].keyId,
        publicKey: keys.oneTimePreKeys[idx].publicKey,
      };
      keys.oneTimePreKeys[idx].isUsed = true;
      await keys.save();
    }

    return res.json({
      success: true,
      data: {
        identityKey: keys.identityKey,
        identitySigningPublic: keys.identitySigningKey,
        signedPreKeyId: keys.signedPreKeyId,
        signedPreKeyPublic: keys.signedPreKeyPublic,
        signedPreKeySignature: keys.signedPreKeySignature,
        oneTimePreKey,
      },
    });
  } catch (e) {
    console.error("keys/bundle error:", e);
    return res.status(500).json({ success: false, message: "Bundle fetch failed" });
  }
});

export default router;
