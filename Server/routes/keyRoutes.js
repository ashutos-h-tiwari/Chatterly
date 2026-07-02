// routes/keyRoutes.js
import express from "express";
import { auth } from "../middlewares/authMiddleware.js";
import UserKeys from "../models/UserKeys.js";

const router = express.Router();
router.use(auth);

// ── POST /api/keys/upload ────────────────────────────────────────────────
router.post("/upload", async (req, res) => {
  try {
    const {
      registrationId,
      identityKey,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      oneTimePreKeys,
    } = req.body;

    if (!identityKey || !signedPreKeyId || !signedPreKeyPublic || !signedPreKeySignature) {
      return res.status(400).json({
        success: false,
        message: "Missing required key material",
      });
    }

    const update = {
      identityKey,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      registrationId: registrationId || null,
      keysUploadedAt: new Date(),
    };

    if (Array.isArray(oneTimePreKeys) && oneTimePreKeys.length > 0) {
      update.oneTimePreKeys = oneTimePreKeys.map((k) => ({
        keyId:     k.keyId,
        publicKey: k.publicKey,
        isUsed:    false,
      }));
    }

    await UserKeys.findOneAndUpdate(
      { user: req.user._id },
      { $set: update },
      { new: true, upsert: true }
    );

    console.log(`✅ Keys uploaded for user ${req.user._id}`);
    return res.json({ success: true });
  } catch (e) {
    console.error("❌ keys/upload error:", e);
    return res.status(500).json({ success: false, message: "Key upload failed" });
  }
});

// ── POST /api/keys/bundle ────────────────────────────────────────────────
router.post("/bundle", async (req, res) => {
  try {
    const { recipientId } = req.body;
    if (!recipientId) {
      return res.status(400).json({ success: false, message: "recipientId required" });
    }

    const keys = await UserKeys.findOne({ user: recipientId });
    if (!keys) {
      return res.status(404).json({
        success: false,
        message: "No key bundle found for this user. They may not have set up E2E yet.",
      });
    }

    let oneTimePreKey = null;
    const idx = (keys.oneTimePreKeys || []).findIndex((k) => !k.isUsed);
    if (idx >= 0) {
      oneTimePreKey = {
        keyId:     keys.oneTimePreKeys[idx].keyId,
        publicKey: keys.oneTimePreKeys[idx].publicKey,
      };
      keys.oneTimePreKeys[idx].isUsed = true;
      await keys.save();
    }

    return res.json({
      success: true,
      data: {
        registrationId:        keys.registrationId,
        identityKey:           keys.identityKey,
        signedPreKeyId:        keys.signedPreKeyId,
        signedPreKeyPublic:    keys.signedPreKeyPublic,
        signedPreKeySignature: keys.signedPreKeySignature,
        oneTimePreKey,
      },
    });
  } catch (e) {
    console.error("❌ keys/bundle error:", e);
    return res.status(500).json({ success: false, message: "Bundle fetch failed" });
  }
});

// ── GET /api/keys/bundle/:userId ─────────────────────────────────────────
router.get("/bundle/:userId", async (req, res) => {
  try {
    const keys = await UserKeys.findOne({ user: req.params.userId });
    if (!keys) {
      return res.status(404).json({ success: false, message: "No key bundle found." });
    }

    let oneTimePreKey = null;
    const idx = (keys.oneTimePreKeys || []).findIndex((k) => !k.isUsed);
    if (idx >= 0) {
      oneTimePreKey = {
        keyId:     keys.oneTimePreKeys[idx].keyId,
        publicKey: keys.oneTimePreKeys[idx].publicKey,
      };
      keys.oneTimePreKeys[idx].isUsed = true;
      await keys.save();
    }

    return res.json({
      success: true,
      data: {
        registrationId:        keys.registrationId,
        identityKey:           keys.identityKey,
        signedPreKeyId:        keys.signedPreKeyId,
        signedPreKeyPublic:    keys.signedPreKeyPublic,
        signedPreKeySignature: keys.signedPreKeySignature,
        oneTimePreKey,
      },
    });
  } catch (e) {
    console.error("❌ keys/bundle/:userId error:", e);
    return res.status(500).json({ success: false, message: "Bundle fetch failed" });
  }
});

export default router;