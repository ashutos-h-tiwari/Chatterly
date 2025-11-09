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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

// ---------- Helmet (allow cross-origin images like avatars) ----------
app.use(
  helmet({
    crossOriginResourcePolicy: { policy: "cross-origin" },
  })
);

// ---------- CORS: reflect origin + allow Authorization ----------
const corsOptions = {
  origin: true, // reflect the request origin (safer than hardcoding localhost port)
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: [
    "Authorization",
    "authorization",
    "Content-Type",
    "content-type",
  ],
  credentials: false,
  optionsSuccessStatus: 204,
};

app.use(cors(corsOptions));
// Respond to ALL preflights BEFORE anything else
app.options("*", cors(corsOptions), (_req, res) => res.sendStatus(204));

// ---------- Body parser ----------
app.use(express.json({ limit: "1mb" }));

// ---------- Rate limiter: do NOT throttle OPTIONS ----------
const safeLimiter = (req, res, next) => {
  if (req.method === "OPTIONS") return res.sendStatus(204);
  return apiLimiter(req, res, next);
};
app.use(safeLimiter);

// (Optional) extra safety: ensure headers always present
app.use((req, res, next) => {
  const origin = req.headers.origin || "*";
  res.header("Access-Control-Allow-Origin", origin);
  res.header(
    "Access-Control-Allow-Headers",
    "Authorization,authorization,Content-Type,content-type"
  );
  res.header(
    "Access-Control-Allow-Methods",
    "GET,POST,PUT,PATCH,DELETE,OPTIONS"
  );
  if (req.method === "OPTIONS") return res.sendStatus(204);
  return next();
});

// ---------- Static files ----------
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// ---------- Routes ----------
console.log("📍 Registering API routes...");
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/chat", chatRoutes);
console.log("📍 Chat routes registered at /api/chat");

app.get("/", (_req, res) => res.send("✅ Chat backend is running..."));

// ---------- Error handler ----------
app.use(errorHandler);

// ---------- Socket.IO with matching CORS ----------
const io = new IOServer(server, {
  cors: {
    origin: true,
    methods: ["GET", "POST"],
    allowedHeaders: ["Authorization", "Content-Type"],
  },
});
initSocket(io);

// ---------- Start ----------
const PORT = process.env.PORT || 5000;
connectDB(process.env.MONGO_URI)
  .then(() => {
    server.listen(PORT, () =>
      console.log(`🚀 Server listening on http://localhost:${PORT}`)
    );
  })
  .catch((err) => console.error("❌ MongoDB connection failed:", err.message));
