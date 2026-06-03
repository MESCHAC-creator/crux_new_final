const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();
const db = admin.firestore();

const PAYDUNYA_MASTER_KEY = 'Mt8Kupif-RFtT-Cchb-P2vq-p4T4DrZOLtV1';
const PAYDUNYA_PRIVATE_KEY = 'live_private_Ktf6Dx6nVicd5pEqRvSTbKBwNqB';
const PAYDUNYA_TOKEN = 'MXuDgF2N5Vd8LqIsTuzx';
const PAYDUNYA_BASE = 'https://app.paydunya.com/api/v1';

// ── Create PayDunya invoice ──────────────────────────────────────────────────
exports.createPayment = functions.https.onCall(async (data, context) => {
  const { userId, userName, userEmail } = data;
  if (!userId) throw new functions.https.HttpsError('invalid-argument', 'userId required');

  const returnUrl = 'https://crux-8aa85.web.app/payment-success';
  const cancelUrl = 'https://crux-8aa85.web.app/payment-cancel';
  const notifyUrl = `https://us-central1-crux-8aa85.cloudfunctions.net/paydunyaWebhook`;

  const payload = {
    invoice: {
      items: {
        item_0: {
          name: 'Crux Pro - Abonnement mensuel',
          quantity: 1,
          unit_price: '25000',
          total_price: '25000',
          description: 'Réunions illimitées pendant 30 jours',
        },
      },
      taxes: {},
      total_amount: 25000,
      description: 'Crux Pro - Abonnement mensuel 25 000 FCFA',
    },
    store: {
      name: 'Crux Visioconférence',
    },
    custom_data: {
      userId,
      userName: userName || '',
    },
    actions: {
      cancel_url: cancelUrl,
      return_url: returnUrl,
      callback_url: notifyUrl,
    },
  };

  try {
    const response = await axios.post(
      `${PAYDUNYA_BASE}/checkout-invoice/create`,
      payload,
      {
        headers: {
          'PAYDUNYA-MASTER-KEY': PAYDUNYA_MASTER_KEY,
          'PAYDUNYA-PRIVATE-KEY': PAYDUNYA_PRIVATE_KEY,
          'PAYDUNYA-TOKEN': PAYDUNYA_TOKEN,
          'Content-Type': 'application/json',
        },
      }
    );

    const result = response.data;
    if (result.response_code === '00') {
      // Save pending payment in Firestore
      await db.collection('payments').add({
        userId,
        invoiceToken: result.token,
        amount: 25000,
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { paymentUrl: result.response_text, token: result.token };
    } else {
      throw new functions.https.HttpsError('internal', result.response_text);
    }
  } catch (e) {
    throw new functions.https.HttpsError('internal', e.message);
  }
});

// ── PayDunya IPN webhook ─────────────────────────────────────────────────────
exports.paydunyaWebhook = functions.https.onRequest(async (req, res) => {
  try {
    const { data } = req.body;
    if (!data) return res.status(400).send('No data');

    const invoiceToken = data.invoice?.token;
    const status = data.invoice?.status;
    const customData = data.custom_data || {};
    const userId = customData.userId;

    if (status !== 'completed' || !userId || !invoiceToken) {
      return res.status(200).send('ignored');
    }

    // Verify with PayDunya
    const verify = await axios.get(
      `${PAYDUNYA_BASE}/checkout-invoice/confirm/${invoiceToken}`,
      {
        headers: {
          'PAYDUNYA-MASTER-KEY': PAYDUNYA_MASTER_KEY,
          'PAYDUNYA-PRIVATE-KEY': PAYDUNYA_PRIVATE_KEY,
          'PAYDUNYA-TOKEN': PAYDUNYA_TOKEN,
        },
      }
    );

    if (verify.data.status !== 'completed') {
      return res.status(200).send('not completed');
    }

    // Activate Pro for 30 days
    const proExpiry = new Date();
    proExpiry.setDate(proExpiry.getDate() + 30);

    await db.collection('users').doc(userId).set(
      {
        isPro: true,
        proExpiry: admin.firestore.Timestamp.fromDate(proExpiry),
        lastPayment: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Update payment record
    const paymentsRef = db.collection('payments');
    const q = await paymentsRef.where('invoiceToken', '==', invoiceToken).get();
    q.forEach((doc) => doc.ref.update({ status: 'completed' }));

    return res.status(200).send('ok');
  } catch (e) {
    console.error('Webhook error:', e);
    return res.status(500).send('error');
  }
});
