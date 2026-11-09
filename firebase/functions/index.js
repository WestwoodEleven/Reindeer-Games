// Reindeer Games: sends phone alerts to the iPhone app.
// Keeps the game's secret: a steal alert names the house the reindeer was
// taken FROM, never the house that has him now.
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');

initializeApp();
const db = getFirestore();

async function familyOf(homeId) {
  if (!homeId) return null;
  const d = await db.doc('homes/' + homeId).get();
  return d.exists ? d.data().family || null : null;
}

// Send to every registered phone that wants this kind of alert, except the person who caused it.
// kind: 'steals' | 'posts' | 'replies'. Each phone also chooses whether alerts make a sound.
async function sendAll({ title, body, exceptUid, link, onlyUids, kind }) {
  const snap = await db.collection('devices').get();
  const loud = [], quiet = [];
  snap.docs.forEach(d => {
    const v = d.data(), prefs = v.prefs || {};
    if (v.uid === exceptUid) return;
    if (onlyUids && !onlyUids.has(v.uid)) return;
    if (kind && prefs[kind] === false) return;
    (prefs.sound ? loud : quiet).push(d.id);
  });
  for (const [tokens, sound] of [[loud, true], [quiet, false]]) {
    for (let i = 0; i < tokens.length; i += 500) {
      const batch = tokens.slice(i, i + 500);
      const res = await getMessaging().sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: { link: link || '#feed' },
        apns: { payload: { aps: sound ? { sound: 'default' } : {} } },
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
}

exports.stealAlert = onDocumentCreated('steals/{id}', async (event) => {
  const s = event.data && event.data.data();
  if (!s) return;
  if (s.kind === 'start') {
    await sendAll({ title: '🦌 Let the games begin!', body: 'Rudolph is on the loose! Find him and steal him.', link: '#feed', kind: 'steals' });
    return;
  }
  if (s.kind !== 'steal') return;
  // Skip old steals typed in after the fact (e.g. filling a gap in the trail).
  const at = Date.parse(s.at || '') || s.createdAt || Date.now();
  if (Date.now() - at > 24 * 60 * 60 * 1000) return;
  const from = await familyOf(s.from);
  await sendAll({
    title: '🦌 The reindeer was stolen!',
    body: from ? `He was taken from ${from.replace(/^The\s/, 'the ')}. Who has him now? Go look.` : 'Who has him now? Go look.',
    exceptUid: s.by,
    link: '#feed',
    kind: 'steals',
  });
});

exports.postAlert = onDocumentCreated('posts/{id}', async (event) => {
  const p = event.data && event.data.data();
  if (!p) return;
  const text = (p.text || '').trim();
  // A photo-only post is announced by mediaAlert once the photo arrives.
  if (!text) return;
  const fam = (await familyOf(p.byHome)) || 'A neighbor';
  await sendAll({
    title: fam,
    body: text.length > 140 ? text.slice(0, 137) + '…' : text,
    exceptUid: p.by,
    link: '#feed',
    kind: 'posts',
  });
});

exports.mediaAlert = onDocumentCreated('media/{id}', async (event) => {
  const m = event.data && event.data.data();
  if (!m) return;
  const id = event.params.id;
  // One alert per batch: skip if this person uploaded something in the last 3 minutes.
  const now = Date.parse(m.at || '') || Date.now();
  const recent = await db.collection('media').where('by', '==', m.by).get();
  const earlier = recent.docs.some(d => {
    if (d.id === id) return false;
    const t = Date.parse(d.data().at || '');
    return t && t <= now && now - t < 3 * 60 * 1000;
  });
  if (earlier) return;
  // A post with words already sent its own alert.
  if (m.postId) {
    const post = await db.doc('posts/' + m.postId).get();
    if (post.exists && (post.data().text || '').trim()) return;
  }
  const what = m.type === 'video' ? 'video' : 'photo';
  if (m.stealId) {
    // Photos of the newest steal stay hidden until he moves again, so don't announce them.
    const steals = await db.collection('steals').get();
    let latest = null;
    steals.docs.forEach(d => { const a = d.data().at || ''; if (!latest || a > latest.at) latest = { id: d.id, at: a }; });
    if (latest && latest.id === m.stealId) return;
    // Capture media: no family name, so it can't give away who has the reindeer.
    await sendAll({
      title: what === 'video' ? '🎥 New capture video' : '📸 New capture photo',
      body: 'Open the feed to see it.',
      exceptUid: m.by,
      link: '#feed',
      kind: 'posts',
    });
    return;
  }
  const fam = (await familyOf(m.byHome)) || 'A neighbor';
  await sendAll({
    title: fam,
    body: what === 'video' ? 'Shared a video.' : 'Shared a photo.',
    exceptUid: m.by,
    link: '#feed',
    kind: 'posts',
  });
});

// Replies alert the post's author and anyone else who replied to that post.
exports.replyAlert = onDocumentCreated('replies/{id}', async (event) => {
  const r = event.data && event.data.data();
  if (!r || !r.postId) return;
  const post = await db.doc('posts/' + r.postId).get();
  if (!post.exists) return;
  const who = new Set([post.data().by]);
  const others = await db.collection('replies').where('postId', '==', r.postId).get();
  others.docs.forEach(d => who.add(d.data().by));
  who.delete(r.by);
  if (!who.size) return;
  const fam = (await familyOf(r.byHome)) || 'A neighbor';
  const text = (r.text || '').trim();
  await sendAll({
    title: `${fam} replied`,
    body: text.length > 140 ? text.slice(0, 137) + '…' : text,
    exceptUid: r.by,
    onlyUids: who,
    link: '#feed',
    kind: 'replies',
  });
});

// Reports and "Rudolph's gone" notes go to the organizers' phones only.
async function organizerUids() {
  const orgs = new Set((await db.collection('organizers').get()).docs.map(d => d.id.toLowerCase()));
  const devices = await db.collection('devices').get();
  const uids = new Set(devices.docs.map(d => d.data().uid).filter(Boolean));
  const out = new Set();
  await Promise.all([...uids].map(async uid => {
    try {
      const u = await getAuth().getUser(uid);
      if ((u.email && orgs.has(u.email.toLowerCase())) || (u.phoneNumber && orgs.has(u.phoneNumber))) out.add(uid);
    } catch (e) { /* deleted user */ }
  }));
  return out;
}

exports.reportAlert = onDocumentCreated('reports/{id}', async (event) => {
  const r = event.data && event.data.data();
  if (!r) return;
  const uids = await organizerUids();
  if (!uids.size) return;
  const fam = (await familyOf(r.byHome)) || 'A family';
  const missing = r.type === 'missing';
  await sendAll({
    title: missing ? `${fam} says Rudolph is gone` : 'New report to review',
    body: missing ? 'Nobody has logged the steal yet. Check your organizer page.' : `${fam} reported something: ${r.reason || 'see your organizer page'}.`,
    onlyUids: uids,
    link: '#admin',
  });
});
