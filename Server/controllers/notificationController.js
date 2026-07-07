import User from "../models/User.js";

export const saveFcmToken = async (req, res) => {
  try {
    const userId = req.user.id;          // from JWT
    const { fcmToken } = req.body;

    if (!fcmToken) {
      return res.status(400).json({ message: "FCM token required" });
    }

    await User.findByIdAndUpdate(userId, {
      fcmToken
    });

    res.json({ message: "FCM token saved" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};