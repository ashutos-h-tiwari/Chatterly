import express from "express";
import { saveFcmToken } from "../controllers/notificationController.js";
import { protect } from "../middlewares/authMiddleware.js";

const router = express.Router();

// Save / update FCM token
router.post("/fcm-token", protect, saveFcmToken);

export default router;