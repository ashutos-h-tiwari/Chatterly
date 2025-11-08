// src/server.js
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
import { apiLimiter } from "./middlewares/rateLimiter.js";
import { errorHandler } from "./middlewares/errorHandler.js";
import { initSocket } from "./utils/socketUtils.js";

dotenv.config();

// ✅ ESM fix for __dirname / __filename
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

/* --------------------------------- SECURITY -------------------------------- */

app.use(
  helmet({
    // Serving images/files from /uploads to web origins:
    crossOriginResourcePolicy: { policy: "cross-origin" },
  })
);

/* ----------------------------------- CORS ---------------------------------- */

// Allowed origins (env takes priority; include dev defaults)
const defaultDevOrigins = [
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://localhost:53600",
  "http://127.0.0.1:53600",
];

const envOrigins = (process.env.FRONTEND_ORIGINS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const allowedOrigins = [...new Set([...envOrigins, ...defaultDevOrigins])];

const corsOptions = {
  origin(origin, cb) {
    // Allow requests with no origin (mobile apps, curl, Postman)
    if (!origin) return cb(null, true);
    if (allowedOrigins.includes(origin)) return cb(null, true);
    console.warn("❌ CORS blocked origin:", origin);
    return cb(new Error("Not allowed by CORS"));
  },
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true, // set to false if you never use cookies
  optionsSuccessStatus: 204,
  maxAge: 600,
};

// Must be BEFORE any routes
app.use(cors(corsOptions));
// Fast lane for all preflights
app.options("*", cors(corsOptions));
// Optional: explicitly 200 for OPTIONS so no middleware blocks it
app.use((req, res, next) => {
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

/* --------------------------------- PARSERS --------------------------------- */

app.use(express.json({ limit: "1mb" }));
app.use(apiLimiter);

/* --------------------------------- STATIC ---------------------------------- */

app.use("/uploads", express.static(path.join(__dirname, "uploads")));

/* --------------------------------- ROUTES ---------------------------------- */

console.log("📍 Registering API routes...");
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/chat", chatRoutes);
console.log("📍 Chat routes registered at /api/chat");

// Health/root
app.get("/", (_req, res) => res.send("✅ Chat backend is running..."));

// Debug: list top-level routes once at boot (dev aid)
if (app._router?.stack) {
  app._router.stack.forEach((layer) => {
    if (layer.route?.path) console.log("📍 Route:", layer.route.path);
  });
}

/* ------------------------------- ERROR HANDLER ------------------------------ */

app.use(errorHandler);

/* --------------------------------- SOCKET.IO -------------------------------- */

const io = new IOServer(server, {
  cors: {
    origin(origin, cb) {
      if (!origin) return cb(null, true);
      if (allowedOrigins.includes(origin)) return cb(null, true);
      console.warn("❌ Socket.IO CORS blocked origin:", origin);
      cb(new Error("Not allowed by CORS"));
    },
    methods: ["GET", "POST"],
    allowedHeaders: ["Authorization"],
    credentials: true,
  },
});
initSocket(io);

/* --------------------------------- STARTUP --------------------------------- */

const PORT = process.env.PORT || 5000;

connectDB(process.env.MONGO_URI)
  .then(() => {
    server.listen(PORT, () => {
      console.log(`🚀 Server listening on http://localhost:${PORT}`);
      console.log("✅ Allowed CORS origins:", allowedOrigins.join(", ") || "(none)");
    });
  })
  .catch((err) => {
    console.error("❌ MongoDB connection failed:", err.message);
    process.exit(1);
  });
