import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

import {
  BLOCKLIST_DOC,
  SITE_WP_USER_IDS,
  enforceRefusal,
  isBlocked,
  loadBlocklist,
  mayOwnListings,
} from './directory.ts';

/**
 * The admin portal's "Never give this account the directory" tool.
 *
 * Grace, 2026-09-30, about the site account: listings must never be
 * assigned to her, and she wanted to run it against that one account and
 * read what happened. So this reports, line by line, everything that decides
 * whether an account can be handed listings and everything it currently
 * holds, and with `apply` it puts every identifier the account has on the
 * block list and cleans up exactly as a release does.
 *
 * The lines are the product: the admin page prints them in its console and
 * offers them to copy.
 */
export async function blockDirectoryAccount(
  uid: string,
  { apply }: { apply: boolean },
): Promise<{ log: string[]; blocked: boolean }> {
  const db = getFirestore();
  const log: string[] = [];
  const say = (line: string) => log.push(line);

  say(`${apply ? 'BLOCK' : 'CHECK'} account ${uid}`);

  let authEmail = '';
  try {
    const user = await getAuth().getUser(uid);
    authEmail = (user.email ?? '').toLowerCase();
    say(`  sign-in email      ${authEmail || '(none)'}${user.emailVerified ? ' (verified)' : ''}`);
  } catch {
    say('  sign-in account    not found (a shell profile, or a deleted account)');
  }

  const profile = (await db.collection('users').doc(uid).get()).data() ?? {};
  say(`  profile            ${String(profile.name ?? '(no name)')} ${String(profile.handle ?? '')}`.trimEnd());

  const linkSnap = await db.collection('directory').doc(uid).get();
  const link = linkSnap.data() ?? {};
  const wpUserId = Number(link.wpUserId);
  const wpEmail = String(link.wpEmailLower ?? '').toLowerCase();
  if (!linkSnap.exists) {
    say('  website link       none: this account has never linked to littlebluecart.com');
  } else {
    say(`  website link       ${String(link.status ?? '?')}`);
    say(`  website account    user ${Number.isFinite(wpUserId) ? wpUserId : '?'} ${String(link.wpLogin ?? '')}`.trimEnd());
    say(`  website email      ${wpEmail || '(none)'}`);
    const roles = Array.isArray(link.wpRoles) ? link.wpRoles.join(', ') : '';
    say(`  website roles      ${roles || '(not recorded)'}`);
    say(`  ownsListings       ${String(link.ownsListings ?? '(unset)')}`);
    say(`  ownershipLocked    ${String(link.ownershipLocked ?? '(unset)')}`);
    if (link.ownershipRefusedReason) say(`  refused because    ${String(link.ownershipRefusedReason)}`);
  }

  const blocklist = await loadBlocklist();
  const listed = isBlocked(blocklist, {
    uid,
    emailLower: authEmail,
    wpUserId: Number.isFinite(wpUserId) ? wpUserId : undefined,
  }) || (wpEmail !== '' && isBlocked(blocklist, { emailLower: wpEmail }));
  say(`  on the block list  ${listed ? 'yes' : 'no'}`);
  say(`  site staff by id   ${SITE_WP_USER_IDS.has(wpUserId) ? 'yes' : 'no'}`);
  say(`  may own listings   ${linkSnap.exists ? (mayOwnListings(link, blocklist, uid) ? 'YES' : 'no') : 'no link'}`);

  const held = await db.collection('directoryListings').where('ownerUid', '==', uid).get();
  const posts = await db.collection('posts').where('authorId', '==', uid).get();
  const directoryPosts = posts.docs.filter((d) => d.id.startsWith('directory_'));
  say(`  listings held      ${held.size}`);
  for (const doc of held.docs.slice(0, 15)) {
    say(`    ${doc.id}  ${String(doc.data().title ?? '')}`);
  }
  if (held.size > 15) say(`    …and ${held.size - 15} more`);
  say(`  directory posts    ${directoryPosts.length}`);

  if (!apply) {
    say('');
    say('Nothing was changed. Press "Block forever" to block it and clean up.');
    return { log, blocked: listed };
  }

  // Every identifier this account has, so changing one of them later (a new
  // email on the app, a different website login) does not get round it.
  const emails = [authEmail, wpEmail].filter(Boolean);
  const ids = Number.isFinite(wpUserId) && wpUserId > 0 ? [wpUserId] : [];
  await db.doc(BLOCKLIST_DOC).set(
    {
      uids: FieldValue.arrayUnion(uid),
      ...(emails.length ? { emails: FieldValue.arrayUnion(...emails) } : {}),
      ...(ids.length ? { wpUserIds: FieldValue.arrayUnion(...ids) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  say('');
  say(`  added to the block list: account ${uid}${emails.length ? `, ${emails.join(', ')}` : ''}${ids.length ? `, website user ${ids[0]}` : ''}`);

  await enforceRefusal(uid, 'an admin has blocked this account from ever owning directory listings', ids[0]);
  if (linkSnap.exists) {
    await db.collection('directory').doc(uid).set(
      {
        ownershipLocked: true,
        ownsListings: false,
        ownershipRefusedReason: 'an admin has blocked this account from ever owning directory listings',
      },
      { merge: true },
    );
  }

  const after = await db.collection('directoryListings').where('ownerUid', '==', uid).count().get();
  const postsAfter = (await db.collection('posts').where('authorId', '==', uid).get()).docs.filter((d) =>
    d.id.startsWith('directory_'),
  ).length;
  say(`  listings held now  ${after.data().count}  (were ${held.size}; they are unclaimed again)`);
  say(`  directory posts    ${postsAfter}  (were ${directoryPosts.length})`);
  say('  locked             yes. "Allow it again" lifts a lock but not the block list.');
  say('');
  say('Done.');

  logger.warn('Directory account blocked by an admin', {
    uid,
    emails,
    wpUserIds: ids,
    released: held.size,
  });
  return { log, blocked: true };
}
