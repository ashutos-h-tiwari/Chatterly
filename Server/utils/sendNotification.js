import admin from "firebase-admin";
import { createRequire } from "module";

if (!admin.apps.length) {
  const require = createRequire(import.meta.url);
  const serviceAccount = require("../config/serviceAccountKey.json");
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

export const sendPushNotification = async ({ fcmToken, title, body, data = {} }) => {
  if (!fcmToken) return;
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