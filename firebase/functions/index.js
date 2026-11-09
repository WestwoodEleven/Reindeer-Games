// Reindeer Games: sends phone alerts to the iPhone app.
// Keeps the game's secret: a steal alert names the house the reindeer was
// taken FROM, never the house that has him now.
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();

async function familyOf(homeId) {
  if (!homeId) return null;
  const d = await db.doc('homes/' + homeId).get();
  return d.exists ? d.data().family || null : null;
}

// Send to every registered phone except the person who caused the alert.
async function sendAll({ title, body, exceptUid, link }) {
  const snap = await db.collection('devices').get();
  const tokens = snap.docs.filter(d => d.data().uid !== exceptUid).map(d => d.id);
  for (let i = 0; i < tokens.length; i += 500) {
    const batch = tokens.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      data: { link: link || '#feed' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    // Forget phones that uninstalled the app or turned alerts off.
    await Promise.all(res.responses.map((r, j) => {
      const code = r.error && r.error.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        return db.doc('devices/' + batch[j]).delete().catch(() => {});
      }
      return null;
    }));
  }
}

exports.stealAlert = onDocumentCreated('steals/{id}', async (event) => {
  const s = event.data && event.data.data();
  if (!s || s.kind !== 'steal') return;
  // Skip old steals typed in after the fact (e.g. filling a gap in the trail).
  const at = Date.parse(s.at || '') || s.createdAt || Date.now();
  if (Date.now() - at > 24 * 60 * 60 * 1000) return;
  const from = await familyOf(s.from);
  await sendAll({
    title: '🦌 The reindeer was stolen!',
    body: from ? `He was taken from ${from}. Who has him now? Go look.` : 'Who has him now? Go look.',
    exceptUid: s.by,
    link: '#feed',
  });
});

exports.postAlert = onDocumentCreated('posts/{id}', async (event) => {
  const p = event.data && event.data.data();
  if (!p) return;
  const fam = (await familyOf(p.byHome)) || 'A neighbor';
  const text = (p.text || '').trim();
  await sendAll({
    title: fam,
    body: text ? (text.length > 140 ? text.slice(0, 137) + '…' : text) : 'Shared something new in the feed.',
    exceptUid: p.by,
    link: '#feed',
  });
});
