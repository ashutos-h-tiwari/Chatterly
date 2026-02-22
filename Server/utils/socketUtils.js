// utils/socket.js
import jwt from "jsonwebtoken";
import Message from "../models/Message.js";
import Conversation from "../models/Conversation.js";

let ioRef = null;
export const getIO = () => ioRef;

// ✅ TURN/ICE SERVER CONFIGURATION
const ICE_SERVERS = [
  {
    urls: "stun:stun.l.google.com:19302", // Google STUN (requires no auth)
  },
  {
    urls: "stun:stun1.l.google.com:19302",
  },
  // ✅ Add your TURN servers (for NAT/firewall traversal)
  // Option 1: Public TURN (if available)
  // {
  //   urls: ["turn:your-turn-server.com:3478"],
  //   username: "user",
  //   credential: "pass"
  // },
  // Option 2: Use metered TURN (Metered.ca, Twilio, etc.) if needed
];

// ✅ Validate SDP format (basic check)
const validateSDP = (sdp) => {
  if (!sdp || typeof sdp !== "string") return false;
  return sdp.includes("v=0") && (sdp.includes("m=audio") || sdp.includes("m=video"));
};

// ✅ Validate ICE candidate format
const validateCandidate = (candidate) => {
  if (!candidate) return true; // end-of-candidates is null
  return typeof candidate === "object" && (candidate.candidate || candidate.sdpMLineIndex !== undefined);
};

/**
 * initSocket(io)
 * - Sets up socket.io event handlers for messaging, delivery/read receipts,
 *   presence, conversation join/leave, and WebRTC signalling (calls).
 */
export const initSocket = (io) => {
  ioRef = io;

  // Track active calls per conversation (conversationId -> call metadata)
  const activeCalls = new Map();
  
  // ✅ Auto-cleanup stale calls after 30 minutes
  const callCleanupInterval = setInterval(() => {
    const now = Date.now();
    for (const [convId, call] of activeCalls.entries()) {
      const elapsed = now - (call.startedAt || call.initiatedAt || 0);
      if (elapsed > 30 * 60 * 1000) { // 30 minutes
        console.log(`🧹 Cleaning up stale call in conversation ${convId}`);
        activeCalls.delete(convId);
      }
    }
  }, 5 * 60 * 1000); // check every 5 minutes

  io.on("connection", async (socket) => {
    try {
      // Accept token from auth or query (backwards compatibility)
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) {
        console.warn("❌ Token missing — disconnecting socket:", socket.id);
        return socket.disconnect(true);
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.id?.toString?.() ?? decoded.id;
      console.log(`✅ Socket Connected: ${socket.id} | User: ${socket.userId}`);

      // Join user's personal room for direct signaling (one or more sockets per user)
      socket.join(socket.userId);

      // Broadcast presence to other sockets
      socket.broadcast.emit("user:online", { userId: socket.userId });

      // Track conversations this socket has joined
      socket.joinedConversations = new Set();

      /* ------------------------
         Conversation join/leave
      ------------------------- */
      const joinHandler = ({ conversationId, roomId }) => {
        try {
          const convId = (conversationId || roomId || "").toString();
          if (!convId) return;
          socket.join(convId);
          socket.joinedConversations.add(convId);
          console.log(`🟢 ${socket.userId} joined conversation ${convId}`);
        } catch (err) {
          console.error("joinHandler error:", err?.message || err);
        }
      };
      const leaveHandler = ({ conversationId, roomId }) => {
        try {
          const convId = (conversationId || roomId || "").toString();
          if (!convId) return;
          socket.leave(convId);
          socket.joinedConversations.delete(convId);
          console.log(`🔴 ${socket.userId} left conversation ${convId}`);
        } catch (err) {
          console.error("leaveHandler error:", err?.message || err);
        }
      };

      socket.on("join:conversation", joinHandler);
      socket.on("leave:conversation", leaveHandler);
      // Backwards-compatible aliases
      socket.on("join", joinHandler);
      socket.on("leave", leaveHandler);

      /* ------------------------
         CHAT: incoming message send
         Expects payload compatible with your createMessageAndBroadcast service
      ------------------------- */
      socket.on("message:send", async (payload) => {
        try {
          const { conversationId } = payload;
          if (!conversationId) {
            return socket.emit("message:error", { message: "Missing conversationId" });
          }

          // Auto-join fallback if socket hasn't joined conversation yet
          if (!socket.joinedConversations.has(String(conversationId))) {
            socket.join(conversationId.toString());
            socket.joinedConversations.add(conversationId.toString());
          }

          // Lazy import/service separation (keeps file lighter in tests)
          const { createMessageAndBroadcast } = await import("../services/socketService.js");
          await createMessageAndBroadcast(ioRef, payload);

          console.log(`📩 Message created and broadcasted for conversation ${conversationId}`);
        } catch (err) {
          console.error("❌ message:send error:", err?.message || err);
          socket.emit("message:error", { message: "Failed to send message" });
        }
      });

      /* ------------------------
         DELIVERY / READ receipts
      ------------------------- */
      socket.on("message:delivered", async ({ conversationId, messageId }) => {
        try {
          if (!conversationId || !messageId) return;
          await Message.findByIdAndUpdate(
            messageId,
            { $addToSet: { deliveredTo: socket.userId } },
            { new: false }
          );
          ioRef.to(conversationId.toString()).emit("message:status", {
            _id: messageId,
            messageId,
            status: "delivered",
          });
        } catch (e) {
          console.error("message:delivered error:", e?.message || e);
        }
      });

      socket.on("message:read", async ({ conversationId, messageId }) => {
        try {
          if (!conversationId || !messageId) return;
          await Message.findByIdAndUpdate(
            messageId,
            { $addToSet: { readBy: socket.userId } },
            { new: false }
          );
          ioRef.to(conversationId.toString()).emit("message:status", {
            _id: messageId,
            messageId,
            status: "read",
          });
        } catch (e) {
          console.error("message:read error:", e?.message || e);
        }
      });

      socket.on("messages:markRead", async ({ conversationId }) => {
        try {
          if (!conversationId) return;
          const ids = await Message.find({
            conversationId,
            sender: { $ne: socket.userId },
            readBy: { $ne: socket.userId },
          }).distinct("_id");

          if (!ids.length) return;

          await Message.updateMany(
            { _id: { $in: ids } },
            { $addToSet: { readBy: socket.userId } }
          );

          ids.forEach((id) => {
            ioRef.to(conversationId.toString()).emit("message:status", {
              _id: id,
              messageId: id,
              status: "read",
            });
          });
        } catch (e) {
          console.error("messages:markRead error:", e?.message || e);
        }
      });

      /* ============================================================
         WEBRTC SIGNALING: call-initiate, call-user, answer-call, ice-candidate, end-call, decline
         Active-calls map prevents races and double-call in same conversation
         ============================================================ */

      /**
       * CALL INITIATE (lightweight notify/ringing)
       * payload: { to, conversationId, fromName?, callType? }
       * emits to callee: 'incoming-call' (without SDP/offer) so receiver can show ringing UI
       * ✅ NOW INCLUDES ICE_SERVERS
       */
      socket.on("call-initiate", async ({ to, conversationId, fromName, callType }) => {
        try {
          if (!to || !conversationId) {
            return socket.emit("call:error", { message: "Missing to/conversationId" });
          }

          // Validate conversation and participants (best-effort)
          const conv = await Conversation.findById(conversationId).select("participants").lean();
          if (!conv) return socket.emit("call:error", { message: "Conversation not found" });

          const participants = conv.participants.map(String);
          if (!participants.includes(String(socket.userId))) {
            return socket.emit("call:error", { message: "You are not a participant in this conversation" });
          }
          if (!participants.includes(String(to))) {
            return socket.emit("call:error", { message: "Callee is not a participant of this conversation" });
          }

          // ✅ Better online check: look for specific user socket
          const calleeSocket = ioRef.sockets.sockets.get(String(to));
          const calleeOnline = calleeSocket && calleeSocket.connected;
          if (!calleeOnline) {
            console.log(`📴 Callee ${to} is offline (initiate)`);
            return socket.emit("callee-offline", { to });
          }

          // Mark conversation as active call (preliminary)
          if (activeCalls.has(String(conversationId))) {
            // still allow notify but also let caller know busy
            socket.emit("call:busy", { conversationId });
            return;
          }

          activeCalls.set(String(conversationId), {
            callerId: socket.userId,
            calleeId: to,
            initiatedAt: Date.now(),
            mode: callType || "voice",
          });

          console.log(`📲 ${socket.userId} initiated call (notify) -> ${to} (conv ${conversationId})`);

          // ✅ Send ICE servers to callee
          ioRef.to(String(to)).emit("incoming-call", {
            from: socket.userId,
            conversationId,
            fromName: fromName || null,
            callType: callType || "voice",
            notifyOnly: true, // indicates no offer attached yet
            iceServers: ICE_SERVERS, // ✅ NEW: TURN/STUN servers
          });
        } catch (err) {
          console.error("❌ call-initiate error:", err?.message || err);
          socket.emit("call:error", { message: "Failed to initiate call" });
        }
      });

      /**
       * CALL USER (full signaling with offer)
       * payload: { to, conversationId, offer, callId? }
       * emits to callee: 'incoming-call' (with offer)
       * ✅ NOW VALIDATES SDP & SENDS ICE_SERVERS
       */
      socket.on("call-user", async ({ to, conversationId, offer, callId }) => {
        try {
          if (!to || !conversationId || !offer) {
            return socket.emit("call:error", {
              message: "Missing to/conversationId/offer",
            });
          }

          // ✅ Validate SDP offer format
          if (!validateSDP(offer.sdp)) {
            return socket.emit("call:error", { message: "Invalid SDP offer format" });
          }

          // Validate conversation & participants
          const conv = await Conversation.findById(conversationId).select("participants").lean();
          if (!conv) return socket.emit("call:error", { message: "Conversation not found" });

          const participants = conv.participants.map(String);
          if (!participants.includes(String(socket.userId))) {
            return socket.emit("call:error", { message: "You are not a participant in this conversation" });
          }
          if (!participants.includes(String(to))) {
            return socket.emit("call:error", { message: "Callee is not a participant of this conversation" });
          }

          // ✅ Better online check
          const calleeSocket = ioRef.sockets.sockets.get(String(to));
          const calleeOnline = calleeSocket && calleeSocket.connected;
          if (!calleeOnline) {
            console.log(`📴 Callee ${to} is offline (call-user)`);
            return socket.emit("callee-offline", { to });
          }

          // Prevent multiple active calls in same conversation
          if (activeCalls.has(String(conversationId))) {
            return socket.emit("call:busy", { conversationId });
          }

          // Mark conversation as active call
          activeCalls.set(String(conversationId), {
            callerId: socket.userId,
            calleeId: to,
            startedAt: Date.now(),
            callId: callId || null,
          });

          console.log(`📞 ${socket.userId} is calling ${to} (conversation ${conversationId})`);

          // ✅ Send offer + ICE servers to callee
          ioRef.to(String(to)).emit("incoming-call", {
            from: socket.userId,
            conversationId,
            offer,
            callId: callId || null,
            iceServers: ICE_SERVERS, // ✅ NEW: TURN/STUN servers
          });
        } catch (err) {
          console.error("❌ call-user error:", err?.message || err);
          socket.emit("call:error", { message: "Failed to make call" });
        }
      });

      /**
       * ANSWER CALL
       * payload: { to, conversationId, answer }
       * emits to caller: 'call-answered'
       */
      socket.on("answer-call", ({ to, conversationId, answer }) => {
        try {
          ioRef.to(String(to)).emit("call-answered", {
            from: socket.userId,
            conversationId,
            answer,
          });

          const call = activeCalls.get(String(conversationId));
          if (call) {
            activeCalls.set(String(conversationId), {
              ...call,
              establishedAt: Date.now(),
            });
          }
        } catch (err) {
          console.error("❌ answer-call error:", err?.message || err);
        }
      });

      /**
       * ICE CANDIDATES
       * payload: { to, conversationId, candidate }
       * ✅ NOW VALIDATES CANDIDATE FORMAT
       */
      socket.on("ice-candidate", ({ to, conversationId, candidate }) => {
        try {
          // ✅ Validate candidate format
          if (!validateCandidate(candidate)) {
            return socket.emit("call:error", { message: "Invalid ICE candidate format" });
          }

          ioRef.to(String(to)).emit("ice-candidate", {
            from: socket.userId,
            conversationId,
            candidate,
          });
        } catch (err) {
          console.error("❌ ice-candidate error:", err?.message || err);
        }
      });

      /**
       * END CALL
       * payload: { to, conversationId, reason? }
       */
      socket.on("end-call", ({ to, conversationId, reason }) => {
        try {
          ioRef.to(String(to)).emit("call-ended", {
            from: socket.userId,
            conversationId,
            reason: reason || null,
          });

          if (conversationId && activeCalls.has(String(conversationId))) {
            activeCalls.delete(String(conversationId));
          }
        } catch (err) {
          console.error("❌ end-call error:", err?.message || err);
        }
      });

      /**
       * DECLINE CALL
       * payload: { to, conversationId, reason? }
       */
      socket.on("call-decline", ({ to, conversationId, reason }) => {
        try {
          ioRef.to(String(to)).emit("call-declined", {
            from: socket.userId,
            conversationId,
            reason: reason || null,
          });

          if (conversationId && activeCalls.has(String(conversationId))) {
            activeCalls.delete(String(conversationId));
          }
        } catch (err) {
          console.error("❌ call-decline error:", err?.message || err);
        }
      });

      /* ============================================================
         📸 STATUS EVENTS: real-time status upload, view, delete
         ============================================================ */

      /**
       * STATUS UPLOAD (Real-time broadcast)
       * payload: { statusId, userId, mediaUrl, mediaType, caption, user }
       * Broadcast new status to all connected users
       */
      socket.on("status:upload", (payload) => {
        try {
          if (!payload || !payload.statusId || !payload.userId) {
            return socket.emit("status:error", { message: "Invalid status payload" });
          }

          console.log(`📸 New status uploaded by ${payload.userId}`);

          // ✅ Broadcast to all users (not just requester)
          ioRef.emit("status:new", {
            statusId: payload.statusId,
            userId: payload.userId,
            mediaUrl: payload.mediaUrl,
            mediaType: payload.mediaType,
            caption: payload.caption || "",
            user: payload.user,
            uploadedAt: new Date(),
          });
        } catch (err) {
          console.error("❌ status:upload error:", err?.message || err);
          socket.emit("status:error", { message: "Failed to upload status" });
        }
      });

      /**
       * STATUS VIEWED (Real-time notification)
       * payload: { statusId, userId, viewer }
       * Notify status owner when someone views their status
       */
      socket.on("status:viewed", (payload) => {
        try {
          if (!payload || !payload.statusId || !payload.userId) {
            return socket.emit("status:error", { message: "Invalid view payload" });
          }

          console.log(`👁️ Status ${payload.statusId} viewed by ${socket.userId}`);

          // ✅ Emit to status owner only
          ioRef.to(String(payload.userId)).emit("status:view-notification", {
            statusId: payload.statusId,
            viewedBy: socket.userId,
            viewerName: payload.viewerName || "Someone",
            viewedAt: new Date(),
          });
        } catch (err) {
          console.error("❌ status:viewed error:", err?.message || err);
        }
      });

      /**
       * STATUS DELETED (Real-time notification)
       * payload: { statusId, userId }
       * Notify all users when a status is deleted
       */
      socket.on("status:delete", (payload) => {
        try {
          if (!payload || !payload.statusId) {
            return socket.emit("status:error", { message: "Invalid delete payload" });
          }

          // Verify ownership (check if deleter is the status owner)
          if (String(payload.userId) !== String(socket.userId)) {
            return socket.emit("status:error", { message: "Not authorized" });
          }

          console.log(`🗑️ Status ${payload.statusId} deleted by ${socket.userId}`);

          // ✅ Broadcast deletion to all users
          ioRef.emit("status:deleted", {
            statusId: payload.statusId,
            userId: payload.userId,
            deletedAt: new Date(),
          });
        } catch (err) {
          console.error("❌ status:delete error:", err?.message || err);
        }
      });

      /* ------------------------
         DISCONNECT: cleanup and notify other participant if in active call
      ------------------------- */
      socket.on("disconnect", () => {
        try {
          console.log(`❌ Socket disconnected: ${socket.id} | User: ${socket.userId}`);
          socket.broadcast.emit("user:offline", { userId: socket.userId });

          // Cleanup any active calls involving this user
          for (const [convId, call] of activeCalls.entries()) {
            if (String(call.callerId) === String(socket.userId) || String(call.calleeId) === String(socket.userId)) {
              activeCalls.delete(convId);

              const other =
                String(call.callerId) === String(socket.userId) ? call.calleeId : call.callerId;

              ioRef.to(String(other)).emit("call-ended", {
                from: socket.userId,
                conversationId: convId,
                reason: "peer-disconnected",
              });
            }
          }
        } catch (err) {
          console.error("disconnect handler error:", err?.message || err);
        }
      });
    } catch (err) {
      console.error("❌ Socket authentication/connection error:", err?.message || err);
      try {
        socket.disconnect(true);
      } catch (e) {
        // ignore
      }
    }
  });

  // ✅ Cleanup interval on server shutdown
  return callCleanupInterval;
};

/**
 * Helper: emitMessageToRoom
 * Use this from other modules to broadcast a message to a conversation room
 */
export function emitMessageToRoom(conversationId, payload) {
  if (!ioRef || !conversationId) return;
  try {
    ioRef.to(conversationId.toString()).emit("message:new", payload);
  } catch (err) {
    console.error("emitMessageToRoom error:", err?.message || err);
  }
}
