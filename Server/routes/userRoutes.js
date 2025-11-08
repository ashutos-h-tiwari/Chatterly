import express from "express";
import { getUsers, getUserById, updateAvatar } from "../controllers/userController.js";
import { auth } from "../middlewares/authMiddleware.js";
import upload from "../middlewares/upload.js"; // ✅ use Cloudinary multer

const router = express.Router();

router.use(auth);

// ✅ Upload user avatar to Cloudinary
router.post("/upload-avatar", upload.single("avatar"), updateAvatar);

// ✅ Existing routes
router.get("/", getUsers);
router.get("/:id", getUserById);

export default router;
