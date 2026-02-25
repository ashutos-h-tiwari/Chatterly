import express from "express";
import { saveFcmToken } from "../controllers/notificationController.js";
import { auth } from "../middlewares/authMiddleware.js";

router.post("/fcm-token", auth, saveFcmToken);

const router = express.Router();

// Save / update FCM token
//router.post("/fcm-token", protect, saveFcmToken);
export default router;