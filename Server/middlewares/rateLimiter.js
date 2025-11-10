import { rateLimit } from "express-rate-limit";

export const apiLimiter = rateLimit({
  windowMs: 60 * 1000,        // 1 minute window
  limit: 100,                 // default limit
  standardHeaders: true,
  legacyHeaders: false,

  // ✅ custom skip logic
  skip: (req) => {
    // 1. Never throttle OPTIONS/preflight
    if (req.method === "OPTIONS") return true;

    // 2. Don't throttle chat routes — realtime endpoints
    if (
      req.path.startsWith("/api/chat/conversations") || // create/get convo + messages
      req.path.startsWith("/api/chat/conversation") ||  // legacy singular path
      req.path.startsWith("/api/chat/messages")
    ) {
      return true;
    }

    return false;
  },

  // optional — give descriptive 429 response
  handler: (req, res) => {
    res.status(429).json({
      success: false,
      message: "Too many requests — please slow down.",
    });
  },
});
