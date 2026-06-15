/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {setGlobalOptions} from "firebase-functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as functions from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import * as admin from "firebase-admin";

// Start writing functions
// https://firebase.google.com/docs/functions/typescript

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

const app = initializeApp();
const db = getFirestore(app, "medguard-data");

export const createUserProfile = functions.auth.user().onCreate(
  async (user: functions.auth.UserRecord) => {
    const uid = user.uid;
    const email = user.email ?? "";
    const displayName = (user.displayName ?? "").trim();
    const fallbackName =
      displayName || (email ? email.split("@")[0] : "User");

    await db.runTransaction(async (tx) => {
      const ref = db.collection("users").doc(uid);
      const snap = await tx.get(ref);
      const existing = snap.exists ? snap.data() ?? {} : {};
      const role = existing["role"] ?? "caretaker";

      tx.set(
        ref,
        {
          firstName: existing["firstName"] ?? fallbackName,
          lastName: existing["lastName"] ?? "",
          email: existing["email"] ?? email,
          role,
          createdAt:
            existing["createdAt"] ??
            admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    logger.info("User profile ensured", {uid});
  },
);

export const notifyCaregiver = onDocumentCreated(
  {
    document: "users/{caretakerUid}/care_events/{eventId}",
    database: "medguard-data",
    region: "asia-south1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const caretakerUid = event.params.caretakerUid as string;
    const caretakerName = (data["caretakerName"] as string) || "Caretaker";
    const action = (data["action"] as string) || "updated";
    const medicineName = (data["medicineName"] as string) || "medicine";
    const dosage = (data["dosage"] as string) || "";
    const title =
      (data["title"] as string) || `${caretakerName} ${action} medicine`;
    const body =
      (data["body"] as string) ||
      (dosage ? `${medicineName} (${dosage})` : medicineName);
    if (!body) return;

    const caregiversSnap = await db
      .collection("users")
      .doc(caretakerUid)
      .collection("caregivers")
      .get();

    if (caregiversSnap.empty) {
      logger.info("No caregivers linked", {caretakerUid});
      return;
    }

    const notificationPayload = {
      caretakerUid,
      caretakerName,
      action,
      medicineName,
      dosage,
      title,
      body,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      serverCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
      actorUid: caretakerUid,
    };

    const tokens: string[] = [];
    for (const caregiverDoc of caregiversSnap.docs) {
      const caregiverUid = caregiverDoc.id;
      await db
        .collection("users")
        .doc(caregiverUid)
        .collection("notifications")
        .add(notificationPayload);

      const devicesSnap = await db
        .collection("users")
        .doc(caregiverUid)
        .collection("devices")
        .get();
      devicesSnap.forEach((doc) => {
        const token = doc.get("fcmToken") as string | undefined;
        if (token) tokens.push(token);
      });
    }

    const uniqueTokens = Array.from(new Set(tokens));
    if (uniqueTokens.length === 0) {
      logger.info("No FCM tokens for caregivers", {caretakerUid});
      return;
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens: uniqueTokens,
      notification: {title, body},
      android: {
        priority: "high",
        notification: {
          channelId: "care_event_channel",
          sound: "default",
        },
      },
      data: {
        caretakerUid,
        eventId: event.params.eventId as string,
        title,
        body,
        action,
        medicineName,
        dosage,
      },
    });

    logger.info("FCM send result", {
      caretakerUid,
      success: response.successCount,
      failure: response.failureCount,
    });
  },
);

// export const helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
