import express from "express";
import dotenv from "dotenv";
import helmet from "helmet";
import cors from "cors";
import http from "http";
import path from "path";
import { fileURLToPath } from "url";
import { Server as IOServer } from "socket.io";

import { connectDB } from "./config/db.js";
import authRoutes from "./routes/authRoutes.js";
import userRoutes from "./routes/userRoutes.js";
import chatRoutes from "./routes/chatRoutes.js";
import { apiLimiter } from "./middlewares/rateLimiter.js"; // see safeLimiter wrapper below
import { errorHandler } from "./middlewares/errorHandler.js";
import { initSocket } from "./utils/socketUtils.js";

dotenv.config();

// ===== ES modules __dirname fix =====
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

// ===== CORS + Helmet (must be BEFORE routes & before any rate-limiter) =====
const ORIGIN = process.env.FRONTEND_ORIGIN || "*";

/**
 * Helmet: allow cross-origin images (for avatars served from /uploads or CDN).
 * Default CORP is "same-origin", which can block <img>/NetworkImage on web.
 */
app.use(
  helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
  })
);

/**
 * CORS: explicitly allow Authorization header and handle OPTIONS for all routes.
 */
const corsOptions = {
  origin: ORIGIN, // e.g. "http://localhost:62267" during dev, or "*" if you don't use cookies
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Authorization", "Content-Type"],
  credentials: false, // set true only if you use cookies/sessions
  optionsSuccessStatus: 204,
};

app.use(cors(corsOptions));
app.options("*", cors(corsOptions)); // IMPORTANT: reply to all preflight

// ===== Body parser (after CORS) =====
app.use(express.json({ limit: "1mb" }));

/**
 * (Optional but recommended)
 * If your existing apiLimiter throttles OPTIONS, wrap/replace it with this safe version
 * or update your limiter to `skip: (req) => req.method === 'OPTIONS'`.
 */
const safeLimiter = (req, res, next) => {
  if (req.method === "OPTIONS") return res.sendStatus(204);
  return apiLimiter(req, res, next);
};
app.use(safeLimiter);

// ===== Static files (avatars, etc.) =====
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// ===== API Routes =====
console.log("📍 Registering API routes...");
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/chat", chatRoutes);
console.log("📍 Chat routes registered at /api/chat");

// Root check
app.get("/", (_req, res) => {
  res.send("✅ Chat backend is running...");
});

// Debug registered route paths (optional)
if (app._router && app._router.stack) {
  app._router.stack.forEach((r) => {
    if (r.route && r.route.path) {
      console.log("📍 Route:", r.route.path);
    }
  });
}

// ===== Error handler (after routes) =====
app.use(errorHandler);

// ===== Socket.IO with matching CORS =====
const io = new IOServer(server, {
  cors: {
    origin: ORIGIN,
    methods: ["GET", "POST"],
    allowedHeaders: ["Authorization", "Content-Type"],
  },
});
initSocket(io);

// ===== Start server after DB connect =====
const PORT = process.env.PORT || 5000;

connectDB(process.env.MONGO_URI)
  .then(() => {
    server.listen(PORT, () =>
      console.log(`🚀 Server listening on http://localhost:${PORT}`)
    );
  })
  .catch((err) => {
    console.error("❌ MongoDB connection failed:", err.message);
  });
