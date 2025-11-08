// middlewares/upload.js
import multer from "multer";
import { CloudinaryStorage } from "multer-storage-cloudinary";
import { v2 as cloudinary } from "cloudinary";

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

const storage = new CloudinaryStorage({
  cloudinary,
  params: async (req, file) => {
    let folder = "Chatterly";
    if (file.fieldname === "avatar") folder = "avatars";
    else if (file.fieldname === "attachment") folder = "chat_attachments";

    return {
      folder,
      resource_type: "auto", // handles any file type
      public_id: `${Date.now()}-${file.originalname}`,
    };
  },
});

const upload = multer({ storage });
export default upload;
