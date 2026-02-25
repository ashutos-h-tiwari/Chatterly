import express from "express";
import { saveFcmToken } from "../controllers/notificationController.js";
import { auth } from "../middlewares/authMiddleware.js";


const router = express.Router();
router.post("/fcm-token", auth, saveFcmToken);

// Save / update FCM token
//router.post("/fcm-token", protect, saveFcmToken);
export default router;