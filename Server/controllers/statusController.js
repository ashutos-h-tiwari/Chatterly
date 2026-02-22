import Status from "../models/Status.js";
import User from "../models/User.js";

// ✅ Upload status (image/video/audio)
export const uploadStatus = async (req, res) => {
  try {
    if (!req.file || !req.file.path) {
      return res.status(400).json({ message: "No file uploaded" });
    }

    const { mediaType, caption } = req.body;

    if (!mediaType || !["image", "video", "audio"].includes(mediaType)) {
      return res.status(400).json({ message: "Invalid mediaType. Must be: image, video, or audio" });
    }

    const status = new Status({
      userId: req.user._id,
      mediaUrl: req.file.path, // Cloudinary URL
      mediaType,
      caption: caption || "",
    });

    await status.save();

    // ✅ Populate user info for broadcast
    const populatedStatus = await status.populate("userId", "name avatar email");

    res.status(201).json({
      message: "Status uploaded successfully",
      status: populatedStatus,
    });
  } catch (err) {
    console.error("❌ Error uploading status:", err.message);
    res.status(500).json({ error: "Status upload failed" });
  }
};

// ✅ Get all statuses from connections (excluding own, within 24h)
export const getStatuses = async (req, res) => {
  try {
    // Get all statuses created in last 24 hours, excluding own
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

    const statuses = await Status.find({
      userId: { $ne: req.user._id },
      createdAt: { $gte: twentyFourHoursAgo },
    })
      .populate("userId", "name avatar email")
      .populate("viewers.userId", "name avatar")
      .sort({ createdAt: -1 });

    // Group statuses by user
    const groupedByUser = {};
    for (const status of statuses) {
      const userId = status.userId._id.toString();
      if (!groupedByUser[userId]) {
        groupedByUser[userId] = {
          user: status.userId,
          statuses: [],
        };
      }
      groupedByUser[userId].statuses.push(status);
    }

    res.json(Object.values(groupedByUser));
  } catch (err) {
    console.error("❌ Error fetching statuses:", err.message);
    res.status(500).json({ error: "Failed to fetch statuses" });
  }
};

// ✅ Get my own statuses
export const getMyStatuses = async (req, res) => {
  try {
    const myStatuses = await Status.find({ userId: req.user._id })
      .populate("userId", "name avatar email")
      .populate("viewers.userId", "name avatar")
      .sort({ createdAt: -1 });

    res.json(myStatuses);
  } catch (err) {
    console.error("❌ Error fetching my statuses:", err.message);
    res.status(500).json({ error: "Failed to fetch statuses" });
  }
};

// ✅ Mark status as viewed (add current user to viewers)
export const markStatusViewed = async (req, res) => {
  try {
    const { statusId } = req.params;

    const status = await Status.findById(statusId);
    if (!status) {
      return res.status(404).json({ message: "Status not found" });
    }

    // Check if already viewed by this user
    const alreadyViewed = status.viewers.some(
      (viewer) => viewer.userId.toString() === req.user._id.toString()
    );

    if (!alreadyViewed) {
      status.viewers.push({
        userId: req.user._id,
        viewedAt: new Date(),
      });
      await status.save();
    }

    const updated = await status.populate("viewers.userId", "name avatar email");

    res.json({
      message: "Status marked as viewed",
      status: updated,
    });
  } catch (err) {
    console.error("❌ Error marking status as viewed:", err.message);
    res.status(500).json({ error: "Failed to mark status as viewed" });
  }
};

// ✅ Delete my status
export const deleteStatus = async (req, res) => {
  try {
    const { statusId } = req.params;

    const status = await Status.findById(statusId);
    if (!status) {
      return res.status(404).json({ message: "Status not found" });
    }

    // Only owner can delete
    if (status.userId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ message: "Not authorized to delete this status" });
    }

    await Status.findByIdAndDelete(statusId);

    res.json({ message: "Status deleted successfully" });
  } catch (err) {
    console.error("❌ Error deleting status:", err.message);
    res.status(500).json({ error: "Failed to delete status" });
  }
};

// ✅ Get status viewers
export const getStatusViewers = async (req, res) => {
  try {
    const { statusId } = req.params;

    const status = await Status.findById(statusId)
      .populate("viewers.userId", "name avatar email");

    if (!status) {
      return res.status(404).json({ message: "Status not found" });
    }

    // Only owner can see viewers
    if (status.userId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ message: "Not authorized" });
    }

    res.json({
      statusId,
      viewersCount: status.viewers.length,
      viewers: status.viewers,
    });
  } catch (err) {
    console.error("❌ Error fetching viewers:", err.message);
    res.status(500).json({ error: "Failed to fetch viewers" });
  }
};
