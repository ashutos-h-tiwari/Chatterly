// utils/socket.js
import jwt from "jsonwebtoken";
import Message from "../models/Message.js";
import Conversation from "../models/Conversation.js";

let ioRef = null;
export const getIO = () => ioRef;

export const initSocket = (io) => {
  ioRef = io;

  // Track active calls per conversation (conversationId -> call metadata)
  const activeCalls = new Map();

  io.on("connection", async (socket) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) {
        console.warn("❌ Token missing — disconnecting socket:", socket.id);
        return socket.disconnect(true);
      }

      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.id?.toString?.() ?? decoded.id;
      console.log(`✅ Socket Connected: ${socket.id} | User: ${socket.userId}`);

      socket.join(socket.userId);
      socket.broadcast.emit("user:online", { userId: socket.userId });
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
      socket.on("join", joinHandler);
      socket.on("leave", leaveHandler);

      /* ------------------------
         CHAT: incoming message send
      ------------------------- */
      socket.on("message:send", async (payload) => {
        try {
          const { conversationId } = payload;
          if (!conversationId) {
            return socket.emit("message:error", { message: "Missing conversationId" });
          }

          if (!socket.joinedConversations.has(String(conversationId))) {
            socket.join(conversationId.toString());
            socket.joinedConversations.add(conversationId.toString());
          }

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
         WEBRTC SIGNALING
         ============================================================ */

      /**
       * CALL INITIATE (lightweight notify/ringing - no offer yet)
       * payload: { to, conversationId, fromName?, callType? }
       */
      socket.on("call-initiate", async ({ to, conversationId, fromName, callType }) => {
        try {
          if (!to || !conversationId) {
            return socket.emit("call:error", { message: "Missing to/conversationId" });
          }

          const conv = await Conversation.findById(conversationId).select("participants").lean();
          if (!conv) return socket.emit("call:error", { message: "Conversation not found" });

          const participants = conv.participants.map(String);
          if (!participants.includes(String(socket.userId))) {
            return socket.emit("call:error", { message: "You are not a participant in this conversation" });
          }
          if (!participants.includes(String(to))) {
            return socket.emit("call:error", { message: "Callee is not a participant of this conversation" });
          }

          const calleeOnline = ioRef.sockets.adapter.rooms.has(String(to));
          if (!calleeOnline) {
            console.log(`📴 Callee ${to} is offline (initiate)`);
            return socket.emit("callee-offline", { to });
          }

          if (activeCalls.has(String(conversationId))) {
            socket.emit("call:busy", { conversationId });
            return;
          }

          // Set preliminary active call entry
          activeCalls.set(String(conversationId), {
            callerId: socket.userId,
            calleeId: to,
            initiatedAt: Date.now(),
            mode: callType || "voice",
            offerSent: false, // ✅ track whether offer has been sent yet
          });

          console.log(`📲 ${socket.userId} initiated call (notify) -> ${to} (conv ${conversationId})`);

          ioRef.to(String(to)).emit("incoming-call", {
            from: socket.userId,
            conversationId,
            fromName: fromName || null,
            callType: callType || "voice",
            notifyOnly: true,
          });
        } catch (err) {
          console.error("❌ call-initiate error:", err?.message || err);
          socket.emit("call:error", { message: "Failed to initiate call" });
        }
      });

      /**
       * CALL USER (full signaling with SDP offer)
       * payload: { to, conversationId, offer, callId? }
       *
       * ✅ FIXED: If call-initiate already set activeCalls for this conversation,
       * we UPDATE the entry instead of returning call:busy.
       * This prevents the offer from being blocked after ringing.
       */
      socket.on("call-user", async ({ to, conversationId, offer, callId }) => {
        try {
          if (!to || !conversationId || !offer) {
            return socket.emit("call:error", {
              message: "Missing to/conversationId/offer",
            });
          }

          const conv = await Conversation.findById(conversationId).select("participants").lean();
          if (!conv) return socket.emit("call:error", { message: "Conversation not found" });

          const participants = conv.participants.map(String);
          if (!participants.includes(String(socket.userId))) {
            return socket.emit("call:error", { message: "You are not a participant in this conversation" });
          }
          if (!participants.includes(String(to))) {
            return socket.emit("call:error", { message: "Callee is not a participant of this conversation" });
          }

          const calleeOnline = ioRef.sockets.adapter.rooms.has(String(to));
          if (!calleeOnline) {
            console.log(`📴 Callee ${to} is offline (call-user)`);
            return socket.emit("callee-offline", { to });
          }

          // ✅ FIXED: Check if this is from the same caller (after call-initiate)
          // If so, update the entry. If it's a completely different caller, then it's busy.
          if (activeCalls.has(String(conversationId))) {
            const existing = activeCalls.get(String(conversationId));

            if (String(existing.callerId) === String(socket.userId)) {
              // Same caller sending offer after initiate — update entry, don't block
              activeCalls.set(String(conversationId), {
                ...existing,
                startedAt: Date.now(),
                callId: callId || null,
                offerSent: true,
              });
            } else {
              // Different caller — truly busy
              return socket.emit("call:busy", { conversationId });
            }
          } else {
            // No prior initiate — set fresh entry
            activeCalls.set(String(conversationId), {
              callerId: socket.userId,
              calleeId: to,
              startedAt: Date.now(),
              callId: callId || null,
              offerSent: true,
            });
          }

          console.log(`📞 ${socket.userId} is calling ${to} (conversation ${conversationId})`);

          ioRef.to(String(to)).emit("incoming-call", {
            from: socket.userId,
            conversationId,
            offer,
            callId: callId || null,
          });
        } catch (err) {
          console.error("❌ call-user error:", err?.message || err);
          socket.emit("call:error", { message: "Failed to make call" });
        }
      });

      /**
       * ANSWER CALL
       * payload: { to, conversationId, answer }
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
       */
      socket.on("ice-candidate", ({ to, conversationId, candidate }) => {
        try {
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

      /* ------------------------
         DISCONNECT
      ------------------------- */
      socket.on("disconnect", () => {
        try {
          console.log(`❌ Socket disconnected: ${socket.id} | User: ${socket.userId}`);
          socket.broadcast.emit("user:offline", { userId: socket.userId });

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
};

export function emitMessageToRoom(conversationId, payload) {
  if (!ioRef || !conversationId) return;
  try {
    ioRef.to(conversationId.toString()).emit("message:new", payload);
  } catch (err) {
    console.error("emitMessageToRoom error:", err?.message || err);
  }
}