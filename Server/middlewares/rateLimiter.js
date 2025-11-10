import { rateLimit } from "express-rate-limit";

export const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 100,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    if (req.method === "OPTIONS") return true;
    // Skip chat & key routes (realtime endpoints)
    if (
      req.path.startsWith("/api/chat/conversations") ||
      req.path.startsWith("/api/chat/conversation") ||
      req.path.startsWith("/api/keys/")
    ) return true;
    return false;
  },
  handler: (_req, res) => {
    res.status(429).json({ success: false, message: "Too many requests — please slow down." });
  },
});
