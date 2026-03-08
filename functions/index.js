const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const crypto = require("crypto");

admin.initializeApp();

const FCM_TOKENS_COLLECTION = "fcm_tokens";
const FCM_MULTICAST_BATCH_SIZE = 500;
const FCM_TOKEN_INACTIVE_DAYS = 90;
// URL de imagen de balón para la notificación (TuCanchaFácil).
const NOTIFICATION_IMAGE_URL = "https://cdn-icons-png.flaticon.com/512/3307/3307972.png";

/** Envía payload a los tokens del snapshot y elimina de Firestore los tokens que FCM marca como inválidos.
 * @param {FirebaseFirestore.QuerySnapshot} snapshot - Snapshot de documentos fcm_tokens con .data().token y .ref
 * @param {object} payload - Payload para admin.messaging().sendEachForMulticast (notification, data, android, etc.)
 * @param {string} [logLabel="FCM"] - Etiqueta para logs al eliminar tokens inválidos
 * @return {Promise<number>} Número de notificaciones enviadas con éxito
 */
async function sendFcmAndCleanInvalidTokens(snapshot, payload, logLabel = "FCM") {
  const docs = snapshot.docs.filter((d) => d.data().token);
  if (docs.length === 0) return 0;
  const tokens = docs.map((d) => d.data().token);
  const refs = docs.map((d) => d.ref);
  let totalSent = 0;
  const toDelete = [];
  for (let i = 0; i < tokens.length; i += FCM_MULTICAST_BATCH_SIZE) {
    const batchTokens = tokens.slice(i, i + FCM_MULTICAST_BATCH_SIZE);
    const batchRefs = refs.slice(i, i + FCM_MULTICAST_BATCH_SIZE);
    const multicast = { ...payload, tokens: batchTokens };
    const response = await admin.messaging().sendEachForMulticast(multicast);
    totalSent += response.successCount;
    response.responses.forEach((r, idx) => {
      if (!r.success && batchRefs[idx]) toDelete.push(batchRefs[idx]);
    });
  }
  if (toDelete.length > 0) {
    const batch = admin.firestore().batch();
    toDelete.forEach((ref) => batch.delete(ref));
    await batch.commit();
    console.log(`${logLabel}: eliminados ${toDelete.length} tokens inválidos`);
  }
  return totalSent;
}

/** Registra o actualiza un token FCM para notificaciones por ciudad.
 * Si se envía deviceId (recomendado), el doc se identifica por hash(deviceId+platform) y siempre
 * se actualiza el mismo documento al refrescar el token. Si no, se usa hash(token) (legacy).
 */
exports.registerFcmToken = onCall(async (request) => {
  const { token, deviceId, ciudadId, platform, lugarId } = request.data || {};
  if (!token || typeof token !== "string" || token.length === 0) {
    throw new HttpsError("invalid-argument", "token es requerido.");
  }
  if (!ciudadId || typeof ciudadId !== "string" || ciudadId.length === 0) {
    throw new HttpsError("invalid-argument", "ciudadId es requerido.");
  }
  const validPlatforms = ["web", "android", "ios"];
  if (!platform || !validPlatforms.includes(platform)) {
    throw new HttpsError("invalid-argument", "platform debe ser web, android o ios.");
  }
  const docId = (deviceId && typeof deviceId === "string" && deviceId.length > 0) ?
    crypto.createHash("sha256").update(`${deviceId}_${platform}`).digest("hex") :
    crypto.createHash("sha256").update(token).digest("hex");
  const docData = {
    token,
    ciudadId,
    platform,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (deviceId && typeof deviceId === "string" && deviceId.length > 0) {
    docData.deviceId = deviceId;
  }
  if (lugarId && typeof lugarId === "string" && lugarId.length > 0) {
    docData.lugarId = lugarId;
  }
  if (request.auth) {
    try {
      const userDoc = await admin.firestore()
        .collection("usuarios")
        .doc(request.auth.uid)
        .get();
      if (userDoc.exists && userDoc.data()) {
        docData.userId = request.auth.uid;
        docData.rol = userDoc.data().rol || "usuario";
      }
    } catch (e) {
      console.warn("registerFcmToken: no se pudo obtener rol del usuario", e.message);
    }
  }
  try {
    await admin.firestore().collection(FCM_TOKENS_COLLECTION).doc(docId).set(docData, { merge: true });
    return { success: true };
  } catch (err) {
    throw new HttpsError("internal", err.message || "Error registrando token.");
  }
});

// Callable: actualiza email y/o contraseña de un usuario en Auth (solo admin/programador).
exports.updateUserAuth = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Debes estar autenticado.");
  }
  const callerUid = request.auth.uid;
  const callerDoc = await admin.firestore().collection("usuarios").doc(callerUid).get();
  const callerRol = callerDoc.exists && callerDoc.data() ? callerDoc.data().rol : null;
  if (callerRol !== "programador" && callerRol !== "superadmin") {
    throw new HttpsError(
      "permission-denied",
      "Solo programador o superadmin pueden actualizar email/contraseña."
    );
  }
  const { uid, newEmail, newPassword } = request.data || {};
  if (!uid || typeof uid !== "string") {
    throw new HttpsError("invalid-argument", "uid es requerido.");
  }
  const email = newEmail || null;
  const password = newPassword || null;
  if (!email && !password) {
    throw new HttpsError("invalid-argument", "Indica newEmail o newPassword.");
  }
  const update = {};
  if (email) update.email = email;
  if (password) update.password = password;
  try {
    await admin.auth().updateUser(uid, update);
    return { success: true };
  } catch (err) {
    throw new HttpsError("internal", err.message || "Error al actualizar usuario.");
  }
});

exports.cleanupPendingReservations = onSchedule("every 10 minutes", async () => {
  const now = admin.firestore.Timestamp.now();
  const oneHourAgo = new Date(now.toDate().getTime() - 60 * 60 * 1000);

  const pendingReservations = await admin.firestore()
    .collection("reservas_pendientes")
    .where("estado", "==", "pendiente")
    .where("expira_en", "<=", oneHourAgo.getTime())
    .get();

  const batch = admin.firestore().batch();

  for (const doc of pendingReservations.docs) {
    const data = doc.data();
    batch.set(
      admin.firestore().collection("reservas_historial").doc(doc.id),
      {
        ...data,
        estado: "expirada",
        procesado_en: admin.firestore.FieldValue.serverTimestamp(),
      }
    );
    batch.delete(doc.ref);
  }

  await batch.commit();
  console.log(`Processed ${pendingReservations.docs.length} expired reservations`);
});

/** Elimina tokens FCM no actualizados en FCM_TOKEN_INACTIVE_DAYS días (limpieza automática). */
exports.cleanupInactiveFcmTokens = onSchedule("every 24 hours", async () => {
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - FCM_TOKEN_INACTIVE_DAYS * 24 * 60 * 60 * 1000)
  );
  const snapshot = await admin.firestore()
    .collection(FCM_TOKENS_COLLECTION)
    .where("updatedAt", "<", cutoff)
    .limit(500)
    .get();

  if (snapshot.empty) {
    console.log("cleanupInactiveFcmTokens: no hay tokens inactivos");
    return;
  }

  const batch = admin.firestore().batch();
  snapshot.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  console.log("cleanupInactiveFcmTokens: eliminados", snapshot.docs.length, "tokens inactivos");
});

/** Elimina promociones viejas (fecha ya pasada) para no acumular datos obsoletos. Ejecuta cada día. */
exports.cleanupExpiredPromociones = onSchedule("every 24 hours", async () => {
  const today = new Date();
  const todayStr = today.getFullYear() + "-" +
    String(today.getMonth() + 1).padStart(2, "0") + "-" +
    String(today.getDate()).padStart(2, "0");

  const db = admin.firestore();
  let totalDeleted = 0;
  let snapshot;

  do {
    snapshot = await db.collection("promociones")
      .where("fecha", "<", todayStr)
      .limit(500)
      .get();

    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach((d) => {
      batch.delete(d.ref);
      totalDeleted++;
    });
    await batch.commit();
  } while (snapshot.docs.length === 500);

  if (totalDeleted > 0) {
    console.log("cleanupExpiredPromociones: eliminadas", totalDeleted, "promociones con fecha <", todayStr);
  } else {
    console.log("cleanupExpiredPromociones: no hay promociones vencidas");
  }
});

// Envía notificación push solo a dispositivos de la ciudad de la promoción (web + móvil)
exports.notifyPromocionCreated = onDocumentCreated("promociones/{promoId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("notifyPromocionCreated: no data");
    return;
  }
  const data = snapshot.data();
  const lugarId = data.lugarId;
  const canchaNombre = data.cancha_nombre || "Cancha";
  const fecha = data.fecha || "";
  const horario = data.horario || "";
  const precioPromocional = data.precio_promocional;
  const nota = data.nota || "";
  const promoId = event.params.promoId;

  let lugarNombre = "TuCanchaFácil";
  let ciudadId = "";
  if (lugarId) {
    try {
      const lugarDoc = await admin.firestore().collection("lugares").doc(lugarId).get();
      if (lugarDoc.exists) {
        const lugarData = lugarDoc.data();
        if (lugarData.nombre) lugarNombre = lugarData.nombre;
        if (lugarData.ciudadId) ciudadId = String(lugarData.ciudadId);
      }
    } catch (e) {
      console.warn("notifyPromocionCreated: no se pudo leer lugar", e.message);
    }
  }

  if (!ciudadId) {
    console.log("notifyPromocionCreated: sin ciudadId, no se envían notificaciones");
    return;
  }

  const precioStr = precioPromocional != null ?
    `$${Number(precioPromocional).toLocaleString("es-CO")}` :
    "";
  const horaInfo = [fecha, horario].filter(Boolean).join(" · ");
  const title = `⚽ Nueva promoción – ${lugarNombre}`;
  let body = `${precioStr}`;
  if (horaInfo) body += ` · ${horaInfo}`;
  if (canchaNombre) body += ` · ${canchaNombre}`;
  if (nota) body += ` – ${nota.substring(0, 80)}${nota.length > 80 ? "…" : ""}`;
  if (!body.trim()) body = "¡Revisa las promociones en TuCanchaFácil!";

  const payload = {
    notification: {
      title,
      body,
      imageUrl: NOTIFICATION_IMAGE_URL,
    },
    data: {
      type: "promocion",
      promocionId: promoId,
      lugarId: String(lugarId || ""),
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "promociones",
        imageUrl: NOTIFICATION_IMAGE_URL,
      },
    },
    apns: {
      payload: { aps: { "mutable-content": 1 } },
      fcmOptions: { imageUrl: NOTIFICATION_IMAGE_URL },
    },
    webpush: {
      notification: {
        title,
        body,
        icon: NOTIFICATION_IMAGE_URL,
        image: NOTIFICATION_IMAGE_URL,
      },
    },
  };

  try {
    const tokensSnap = await admin.firestore()
      .collection(FCM_TOKENS_COLLECTION)
      .where("ciudadId", "==", ciudadId)
      .get();

    const sent = await sendFcmAndCleanInvalidTokens(tokensSnap, payload, "notifyPromocionCreated");
    if (sent === 0 && tokensSnap.docs.length === 0) {
      console.log("notifyPromocionCreated: no tokens for ciudadId", ciudadId);
    } else {
      console.log("notifyPromocionCreated: sent to", sent, "tokens, ciudadId:", ciudadId);
    }
  } catch (err) {
    console.error("notifyPromocionCreated: FCM error", err.message, "promoId:", promoId);
  }
});

/** Envía notificación push cuando una promoción se reactiva tras rechazar una reserva pendiente. */
exports.notifyPromocionReactivated = onDocumentUpdated("promociones/{promoId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const promoId = event.params.promoId;

  // Solo enviar si se reactivó (activo pasó a true) y el motivo es "Reserva rechazada"
  const wasReactivated = after.activo === true &&
    (before.activo === false || before.activo === undefined) &&
    after.motivo_reactivacion === "Reserva rechazada";

  if (!wasReactivated) {
    return;
  }

  const lugarId = after.lugarId;
  const canchaNombre = after.cancha_nombre || "Cancha";
  const fecha = after.fecha || "";
  const horario = after.horario || "";
  const precioPromocional = after.precio_promocional;
  const nota = after.nota || "";

  let lugarNombre = "TuCanchaFácil";
  let ciudadId = "";
  if (lugarId) {
    try {
      const lugarDoc = await admin.firestore().collection("lugares").doc(lugarId).get();
      if (lugarDoc.exists) {
        const lugarData = lugarDoc.data();
        if (lugarData.nombre) lugarNombre = lugarData.nombre;
        if (lugarData.ciudadId) ciudadId = String(lugarData.ciudadId);
      }
    } catch (e) {
      console.warn("notifyPromocionReactivated: no se pudo leer lugar", e.message);
    }
  }

  if (!ciudadId) {
    console.log("notifyPromocionReactivated: sin ciudadId, no se envían notificaciones");
    return;
  }

  const precioStr = precioPromocional != null ?
    `$${Number(precioPromocional).toLocaleString("es-CO")}` :
    "";
  const horaInfo = [fecha, horario].filter(Boolean).join(" · ");
  const title = `⚽ Promoción disponible – ${lugarNombre}`;
  let body = `${precioStr}`;
  if (horaInfo) body += ` · ${horaInfo}`;
  if (canchaNombre) body += ` · ${canchaNombre}`;
  if (nota) body += ` – ${nota.substring(0, 80)}${nota.length > 80 ? "…" : ""}`;
  if (!body.trim()) body = "¡Horario disponible otra vez! Revisa las promociones.";

  const payload = {
    notification: {
      title,
      body,
      imageUrl: NOTIFICATION_IMAGE_URL,
    },
    data: {
      type: "promocion",
      promocionId: promoId,
      lugarId: String(lugarId || ""),
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "promociones",
        imageUrl: NOTIFICATION_IMAGE_URL,
      },
    },
    apns: {
      payload: { aps: { "mutable-content": 1 } },
      fcmOptions: { imageUrl: NOTIFICATION_IMAGE_URL },
    },
    webpush: {
      notification: {
        title,
        body,
        icon: NOTIFICATION_IMAGE_URL,
        image: NOTIFICATION_IMAGE_URL,
      },
    },
  };

  try {
    const tokensSnap = await admin.firestore()
      .collection(FCM_TOKENS_COLLECTION)
      .where("ciudadId", "==", ciudadId)
      .get();

    const sent = await sendFcmAndCleanInvalidTokens(tokensSnap, payload, "notifyPromocionReactivated");
    if (sent === 0 && tokensSnap.docs.length === 0) {
      console.log("notifyPromocionReactivated: no tokens for ciudadId", ciudadId);
    } else {
      console.log("notifyPromocionReactivated: sent to", sent, "tokens, ciudadId:", ciudadId);
    }
  } catch (err) {
    console.error("notifyPromocionReactivated: FCM error", err.message, "promoId:", promoId);
  }
});

/** Envía notificación push a superadmins cuando se crea una auditoría con nivel de riesgo alto o crítico.
 * Las notificaciones llegan SOLO a superadmins del lugar donde se creó la auditoría (filtrado por lugarId). */
exports.notifyAuditAltoRiesgo = onDocumentCreated(
  "auditoria/{auditId}",
  async (event) => {
    const data = event.data ? event.data.data() : null;
    if (!data) return;

    const nivelRiesgo = data.nivel_riesgo || data.nivelRiesgo || "";
    if (nivelRiesgo !== "alto" && nivelRiesgo !== "critico") {
      return;
    }

    const lugarId = data.lugarId || "";
    if (!lugarId) {
      console.log("notifyAuditAltoRiesgo: sin lugarId, no se envían notificaciones");
      return;
    }

    let lugarNombre = "TuCanchaFácil";
    try {
      const lugarDoc = await admin.firestore().collection("lugares").doc(lugarId).get();
      if (lugarDoc.exists && lugarDoc.data() && lugarDoc.data().nombre) {
        lugarNombre = lugarDoc.data().nombre;
      }
    } catch (e) {
      console.warn("notifyAuditAltoRiesgo: no se pudo leer lugar", e.message);
    }

    const accion = data.accion || "Acción registrada";
    const descripcion = data.descripcion || "";
    const usuarioNombre = data.usuario_nombre || "Usuario";
    const nivelLabel = nivelRiesgo === "critico" ? "CRÍTICO" : "ALTO";

    const title = `🚨 Auditoría ${nivelLabel} – ${lugarNombre}`;
    const body = `${usuarioNombre}: ${descripcion || accion}`.substring(0, 120);

    const payload = {
      notification: {
        title,
        body,
        imageUrl: NOTIFICATION_IMAGE_URL,
      },
      data: {
        type: "auditoria",
        auditId: event.params.auditId,
        lugarId,
        nivelRiesgo,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "promociones",
          imageUrl: NOTIFICATION_IMAGE_URL,
        },
      },
      apns: {
        payload: { aps: { "mutable-content": 1 } },
        fcmOptions: { imageUrl: NOTIFICATION_IMAGE_URL },
      },
      webpush: {
        notification: {
          title,
          body,
          icon: NOTIFICATION_IMAGE_URL,
          image: NOTIFICATION_IMAGE_URL,
        },
      },
    };

    try {
      const tokensSnap = await admin.firestore()
        .collection(FCM_TOKENS_COLLECTION)
        .where("lugarId", "==", lugarId)
        .where("rol", "==", "superadmin")
        .get();

      const sent = await sendFcmAndCleanInvalidTokens(tokensSnap, payload, "notifyAuditAltoRiesgo");
      if (sent === 0 && tokensSnap.docs.length === 0) {
        console.log("notifyAuditAltoRiesgo: no hay tokens superadmin para lugarId", lugarId);
      } else {
        console.log("notifyAuditAltoRiesgo: enviado a", sent, "superadmins, lugarId:", lugarId);
      }
    } catch (err) {
      console.error("notifyAuditAltoRiesgo:", err.message);
    }
  },
);
