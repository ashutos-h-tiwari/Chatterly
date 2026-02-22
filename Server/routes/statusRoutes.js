import express from "express";
import { auth } from "../middlewares/authMiddleware.js";
import upload from "../middlewares/upload.js"; // Cloudinary multer

import {
  uploadStatus,
  getStatuses,
  getMyStatuses,
  markStatusViewed,
  deleteStatus,
  getStatusViewers,
} from "../controllers/statusController.js";

const router = express.Router();

// ✅ All routes require authentication
router.use(auth);

/* ---------------------------------------------------
   📸 Status Upload
--------------------------------------------------- */
// ✅ Upload a new status (image/video/audio)
router.post("/upload", upload.single("media"), uploadStatus);

/* ---------------------------------------------------
   👁️ Status Viewing
--------------------------------------------------- */
// ✅ Get all statuses from others (within 24h)
router.get("/", getStatuses);

// ✅ Get my own statuses
router.get("/my-statuses", getMyStatuses);

// ✅ Mark a status as viewed
router.post("/:statusId/view", markStatusViewed);

// ✅ Get viewers of my status
router.get("/:statusId/viewers", getStatusViewers);

/* ---------------------------------------------------
   🗑️ Status Deletion
--------------------------------------------------- */
// ✅ Delete my status
router.delete("/:statusId", deleteStatus);

export default router;
