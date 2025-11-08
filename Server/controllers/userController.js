import User from "../models/User.js";

// ✅ Upload or update avatar
export const updateAvatar = async (req, res) => {
  try {
    if (!req.file || !req.file.path) {
      return res.status(400).json({ message: "No file uploaded" });
    }

    const user = await User.findByIdAndUpdate(
      req.user._id,
      { avatar: req.file.path }, // Cloudinary gives full URL
      { new: true }
    ).select("-password");

    res.status(200).json({
      message: "Avatar uploaded successfully",
      avatarUrl: user.avatar,
      user,
    });
  } catch (err) {
    console.error("❌ Error uploading avatar:", err.message);
    res.status(500).json({ error: "Avatar upload failed" });
  }
};

// ✅ Get all users except current
export const getUsers = async (req, res) => {
  const users = await User.find({ _id: { $ne: req.user._id } }).select("-password");
  res.json(users);
};

// ✅ Get single user
export const getUserById = async (req, res) => {
  const user = await User.findById(req.params.id).select("-password");
  if (!user) return res.status(404).json({ message: "User not found" });
  res.json(user);
};
