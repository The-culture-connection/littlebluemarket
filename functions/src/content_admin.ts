import { FieldValue, getFirestore, type DocumentSnapshot } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Admin: find any post, forum thread, reply, chat message or website-link
 * product, and delete it (Grace, 2026-11-23: "add to the admin portal the
 * ability to delete posts"). Before this the only lever was banning the
 * author, which takes every post they ever made and their sign-in with it.
 *
 * Find takes one search box: a handle, the start of a name, or words from
 * the post or thread itself. Words from a forum thread's title also bring
 * the replies under it, because "the post from Kate under 'favorite
 * eco-friendly packaging supplier?'" is how a reply is naturally described.
 *
 * Every delete writes what it removed to `_internal/moderation/log`, so a
 * mistake can be put back by hand. Counts (comments on a post, threads in a
 * forum) follow by themselves: the counter triggers fire on delete too.
 */

export type ContentKind = 'post' | 'postComment' | 'thread' | 'threadComment' | 'directoryProduct' | 'chat';

export interface FoundContent {
  path: string;
  kind: ContentKind;
  text: string;
  /** The thread title or post a reply sits under. */
  under: string;
  authorUid: string;
  authorName: string;
  authorHandle: string;
  createdAt: string | null;
}

/** Pure: what a path names, or null when it is not something this tool deletes. */
export function parseContentPath(path: unknown): { kind: ContentKind; parts: string[] } | null {
  if (typeof path !== 'string') return null;
  const parts = path.split('/');
  if (parts.some((p) => !p || p === '.' || p === '..')) return null;
  const [a, , c] = parts;
  if (parts.length === 2) {
    if (a === 'posts') return { kind: 'post', parts };
    if (a === 'threads') return { kind: 'thread', parts };
    if (a === 'directoryProducts') return { kind: 'directoryProduct', parts };
    if (a === 'chatroom') return { kind: 'chat', parts };
  }
  if (parts.length === 4 && c === 'comments') {
    if (a === 'posts') return { kind: 'postComment', parts };
    if (a === 'threads') return { kind: 'threadComment', parts };
  }
  return null;
}

/** Pure: does this text contain every word of the query, ignoring case? */
export function matchesWords(text: string, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).map((w) => w.replace(/[^\p{L}\p{N}@#'-]/gu, '')).filter(Boolean);
  if (words.length === 0) return false;
  const hay = text.toLowerCase();
  return words.every((w) => hay.includes(w));
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function when(v: unknown): string | null {
  const t = v as { toDate?: () => Date } | undefined;
  return t?.toDate ? t.toDate().toISOString() : null;
}

const RECENT_SCAN = 1500;
const PER_PERSON = 60;

export async function findContent(query: unknown): Promise<{ items: FoundContent[]; people: number }> {
  const q = str(query).trim();
  if (q.length < 2) throw new HttpsError('invalid-argument', 'Type at least two letters.');
  const db = getFirestore();
  const found = new Map<string, Omit<FoundContent, 'authorName' | 'authorHandle'>>();
  const add = (doc: DocumentSnapshot, kind: ContentKind, under = '') => {
    const d = doc.data() ?? {};
    const text =
      kind === 'thread'
        ? [str(d.title), str(d.body)].filter(Boolean).join(' : ')
        : kind === 'directoryProduct'
          ? [str(d.title), str(d.description)].filter(Boolean).join(' : ')
          : str(d.text) || str(d.caption);
    found.set(doc.ref.path, {
      path: doc.ref.path,
      kind,
      text: text.slice(0, 400),
      under,
      authorUid: str(d.authorId) || str(d.ownerUid),
      createdAt: when(d.createdAt),
    });
  };

  // People: by handle, by the start of a name, or by account id.
  const lower = q.replace(/^@/, '').toLowerCase();
  const uids = new Set<string>();
  const [byHandle, byName, byId] = await Promise.all([
    db.collection('users').where('handleLower', '==', lower).limit(5).get(),
    db.collection('users').where('nameLower', '>=', lower).where('nameLower', '<', `${lower}`).limit(10).get(),
    /^[A-Za-z0-9]{20,40}$/.test(q) ? db.collection('users').doc(q).get() : Promise.resolve(null),
  ]);
  for (const d of [...byHandle.docs, ...byName.docs]) uids.add(d.id);
  if (byId?.exists) uids.add(byId.id);

  for (const uid of uids) {
    const [posts, threads, comments, products, chat] = await Promise.all([
      db.collection('posts').where('authorId', '==', uid).limit(PER_PERSON).get(),
      db.collection('threads').where('authorId', '==', uid).limit(PER_PERSON).get(),
      db.collectionGroup('comments').where('authorId', '==', uid).orderBy('createdAt', 'desc').limit(PER_PERSON).get(),
      db.collection('directoryProducts').where('ownerUid', '==', uid).limit(PER_PERSON).get(),
      db.collection('chatroom').where('authorId', '==', uid).limit(PER_PERSON).get(),
    ]);
    posts.docs.forEach((d) => add(d, 'post'));
    threads.docs.forEach((d) => add(d, 'thread'));
    products.docs.forEach((d) => add(d, 'directoryProduct'));
    chat.docs.forEach((d) => add(d, 'chat'));
    for (const d of comments.docs) {
      const kind = parseContentPath(d.ref.path)?.kind;
      if (kind === 'postComment' || kind === 'threadComment') add(d, kind);
    }
  }

  // Words: the recent threads and posts that contain them, and every reply
  // under a matching thread.
  if (q.length >= 3) {
    const [threads, posts] = await Promise.all([
      db.collection('threads').orderBy('createdAt', 'desc').limit(RECENT_SCAN).get(),
      db.collection('posts').orderBy('createdAt', 'desc').limit(RECENT_SCAN).get(),
    ]);
    const hitThreads = threads.docs.filter((d) => matchesWords(`${str(d.data().title)} ${str(d.data().body)}`, q));
    hitThreads.forEach((d) => add(d, 'thread'));
    for (const t of hitThreads.slice(0, 5)) {
      const replies = await t.ref.collection('comments').limit(200).get();
      replies.docs.forEach((d) => add(d, 'threadComment', str(t.data().title)));
    }
    posts.docs
      .filter((d) => matchesWords(`${str(d.data().text)} ${str(d.data().caption)}`, q))
      .forEach((d) => add(d, 'post'));
  }

  // Replies found by author say what they sit under.
  const parents = new Map<string, string>();
  for (const item of found.values()) {
    if ((item.kind === 'threadComment' || item.kind === 'postComment') && !item.under) {
      parents.set(item.path.split('/').slice(0, 2).join('/'), '');
    }
  }
  if (parents.size) {
    const docs = await db.getAll(...[...parents.keys()].map((p) => db.doc(p)));
    for (const d of docs) parents.set(d.ref.path, str(d.data()?.title) || str(d.data()?.caption) || str(d.data()?.text));
    for (const item of found.values()) {
      if (!item.under) item.under = (parents.get(item.path.split('/').slice(0, 2).join('/')) ?? '').slice(0, 140);
    }
  }

  // Author names, one read each.
  const authors = [...new Set([...found.values()].map((i) => i.authorUid).filter(Boolean))];
  const people = new Map<string, Record<string, unknown>>();
  if (authors.length) {
    const docs = await db.getAll(...authors.map((u) => db.collection('users').doc(u)));
    for (const d of docs) people.set(d.id, d.data() ?? {});
  }
  const items = [...found.values()]
    .map((i) => ({ ...i, authorName: str(people.get(i.authorUid)?.name), authorHandle: str(people.get(i.authorUid)?.handle) }))
    .sort((x, y) => (y.createdAt ?? '').localeCompare(x.createdAt ?? ''))
    .slice(0, 300);
  return { items, people: uids.size };
}

export async function deleteContent(path: unknown, by: string): Promise<{ deleted: string[] }> {
  const parsed = parseContentPath(path);
  if (!parsed) throw new HttpsError('invalid-argument', 'That is not a post, thread, reply, chat message or product.');
  const db = getFirestore();
  const ref = db.doc(parsed.parts.join('/'));
  const snap = await ref.get();
  const deleted: string[] = [];
  const log = (doc: DocumentSnapshot) =>
    db.collection('_internal').doc('moderation').collection('log').add({
      path: doc.ref.path,
      data: doc.data() ?? null,
      deletedBy: by,
      deletedAt: FieldValue.serverTimestamp(),
    });

  if (snap.exists) {
    await log(snap);
    await db.recursiveDelete(ref);
    deleted.push(ref.path);
  }

  // A website-link product and its feed post are one thing to a person.
  const id = parsed.parts[1]!;
  if (parsed.kind === 'directoryProduct' || (parsed.kind === 'post' && id.startsWith('dirproduct_'))) {
    const twin =
      parsed.kind === 'post'
        ? db.collection('directoryProducts').doc(id.slice('dirproduct_'.length))
        : db.collection('posts').doc(`dirproduct_${id}`);
    const t = await twin.get();
    if (t.exists) {
      await log(t);
      await db.recursiveDelete(twin);
      deleted.push(twin.path);
    }
  }

  // Replies to a deleted reply would be left answering nothing.
  if (parsed.kind === 'postComment' || parsed.kind === 'threadComment') {
    const children = await ref.parent.where('parentId', '==', parsed.parts[3]).get();
    for (const c of children.docs) {
      await log(c);
      await db.recursiveDelete(c.ref);
      deleted.push(c.ref.path);
    }
  }

  if (deleted.length === 0) throw new HttpsError('not-found', 'Already gone.');
  logger.info('Admin deleted content', { by, deleted });
  return { deleted };
}
