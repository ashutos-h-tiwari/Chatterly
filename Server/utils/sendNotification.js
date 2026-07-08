import admin from "firebase-admin";
import { createRequire } from "module";

let firebaseReady = false;

// Guard Firebase init so a missing/misconfigured service account file
// degrades to "push notifications disabled" instead of crashing the whole
// server on import (this module is pulled in transitively by chatController
// -> chatRoutes -> server.js, so an unguarded throw here previously would
// have taken chat and E2EE down with it, not just notifications).
if (!admin.apps.length) {
  try {
    const require = createRequire(import.meta.url);
    const serviceAccount = require("../config/serviceAccountKey.json");
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firebaseReady = true;
  } catch (e) {
    console.error(
      "⚠️ Firebase Admin init failed — push notifications disabled:",
      e.message
    );
  }
} else {
  firebaseReady = true;
}

export const sendPushNotification = async ({ fcmToken, title, body, data = {} }) => {
  if (!fcmToken || !firebaseReady) return;
  try {
    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data,
      android: { priority: "high", notification: { sound: "default" } },
      apns: { payload: { aps: { sound: "default" } } },
    });
    console.log("✅ Push notification sent");
  } catch (err) {
    console.error("❌ Push notification failed:", err.message);
  }
};