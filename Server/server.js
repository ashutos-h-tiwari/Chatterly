// server.js (merged, ESM)
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
import keyRoutes from "./routes/keyRoutes.js"; // optional, ensure file exists
import { apiLimiter } from "./middlewares/rateLimiter.js";
import { errorHandler } from "./middlewares/errorHandler.js";
import { initSocket } from "./utils/socketUtils.js";

dotenv.config();

// --- ES module __dirname fix ---
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// --- App & server ---
const app = express();
const server = http.createServer(app);

// ---------- Helmet ----------
app.use(
  helmet({
    // allow cross-origin resource policy when serving images etc
    crossOriginResourcePolicy: { policy: "cross-origin" },
  })
);

// ---------- CORS ----------
const corsOptions = {
  origin: true, // allow any; change to specific origin or function for production
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Authorization", "authorization", "Content-Type", "content-type"],
  credentials: false,
  optionsSuccessStatus: 204,
};
app.use(cors(corsOptions));
app.options("*", cors(corsOptions), (_req, res) => res.sendStatus(204));

// ---------- Body parser ----------
app.use(express.json({ limit: "4mb" })); // increase if you need larger payloads

// ---------- Rate limiter (skip OPTIONS inside) ----------
// Some clients send OPTIONS preflight — skip limiting them to avoid accidental blocks
const safeLimiter = (req, res, next) => {
  if (req.method === "OPTIONS") return res.sendStatus(204);
  return apiLimiter(req, res, next);
};
app.use(safeLimiter);

// Extra headers (defensive)
app.use((req, res, next) => {
  const origin = req.headers.origin || "*";
  res.header("Access-Control-Allow-Origin", origin);
  res.header("Access-Control-Allow-Headers", "Authorization,authorization,Content-Type,content-type");
  res.header("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

// ---------- Static files ----------
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// ---------- API Routes ----------
console.log("📍 Registering API routes...");
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/chat", chatRoutes);

// Optional keys route (E2EE key handling)
try {
  if (keyRoutes) {
    app.use("/api/keys", keyRoutes);
    console.log("📍 Key routes registered at /api/keys");
  }
} catch (e) {
  // if keyRoutes not present or import fails, continue gracefully
  console.log("ℹ️ keyRoutes not registered:", e.message || e);
}

app.get("/", (_req, res) => res.send("✅ Chat backend is running..."));

// ---------- Error handler (must be after routes) ----------
app.use(errorHandler);

// ---------- Socket.IO ----------
const io = new IOServer(server, {
  cors: {
    origin: true, // allow all origins; lock this down in production
    methods: ["GET", "POST"],
    allowedHeaders: ["Authorization", "Content-Type"],
  },
  pingInterval: 20000,
  pingTimeout: 25000,
});
initSocket(io);

// ---------- Start server ----------
const PORT = process.env.PORT || 5000;

connectDB(process.env.MONGO_URI)
  .then(() => {
    server.listen(PORT, () => {
      console.log(`🚀 Server listening on http://localhost:${PORT}`);
    });
  })
  .catch((err) => {
    console.error("❌ MongoDB connection failed:", err?.message ?? err);
    process.exit(1);
  });
