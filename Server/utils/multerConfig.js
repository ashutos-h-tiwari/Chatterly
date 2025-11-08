import multer from "multer";

// Configure where and how files are stored
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, "uploads/"), // folder path
  filename: (req, file, cb) => cb(null, `${Date.now()}_${file.originalname}`)
});

// Optional: filter allowed file types
const fileFilter = (req, file, cb) => {
  const allowed = ["image/jpeg", "image/png", "image/jpg"];
  if (allowed.includes(file.mimetype)) cb(null, true);
  else cb(new Error("Only JPG, JPEG, and PNG files are allowed"), false);
};

// Export configured multer instance
export const upload = multer({ storage, fileFilter });
