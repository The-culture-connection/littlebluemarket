import { FieldValue, getFirestore } from 'firebase-admin/firestore';

/**
 * The starter forums Grace approved on 2026-10-21 ("go on all of them"),
 * posted from the admin portal by the admin who presses the button.
 *
 * A button rather than a script: the forums are the live Community, and the
 * person posting them is the person whose name is on them. Pressing it
 * twice is safe. A forum whose title is already taken (any case) is left
 * alone along with its threads, so nothing is ever doubled.
 */

export interface StarterThread {
  title: string;
  body: string;
}

export interface StarterForum {
  title: string;
  description: string;
  tags: string[];
  threads: StarterThread[];
}

export const STARTER_FORUMS: StarterForum[] = [
  {
    title: 'Getting Started Selling',
    description: 'New to selling? Ask anything, no question too small.',
    tags: ['#selling'],
    threads: [
      {
        title: 'What was your very first sale, and how did the buyer find you?',
        body: 'Everybody remembers their first one. Tell us yours.',
      },
      {
        title: 'How do you price handmade work? Materials, time, or gut feeling?',
        body: 'Share how you landed on your prices, and what you would change.',
      },
      {
        title: 'What do you wish someone had told you before you opened your shop?',
        body: 'Your best advice for the next person starting out.',
      },
    ],
  },
  {
    title: 'Photos and Listings',
    description: 'Make your products look as good in the app as they do in person.',
    tags: ['#listings'],
    threads: [
      {
        title: 'Share your best product photo tip, phone cameras only',
        body: 'Light, backgrounds, angles. Tap Tag a product to show one of yours.',
      },
      {
        title: 'Short and sweet or the full story: how long are your product descriptions?',
        body: 'Tag a listing you are proud of and tell us why it works.',
      },
    ],
  },
  {
    title: 'Small Business Finds',
    description: 'For shoppers: the great things you found here.',
    tags: ['#shopsmall'],
    threads: [
      {
        title: 'What is the best small business find you made this month?',
        body: 'Tag the product so everyone can see it.',
      },
      {
        title: 'Gift ideas under $25 from shops on Little Blue Market',
        body: 'Tag your favourites. The holidays are coming.',
      },
      {
        title: 'Which shop deserves way more love than it gets?',
        body: 'Tag them with Tag someone and tell us why.',
      },
    ],
  },
  {
    title: 'Marketing and the Holiday Season',
    description: 'Getting the word out, especially as the holidays come up.',
    tags: ['#marketing'],
    threads: [
      {
        title: 'Which platform brings you the most customers right now?',
        body: 'Instagram, TikTok, markets, word of mouth? What is working for you.',
      },
      {
        title: 'Share your holiday promotion ideas. What are you planning?',
        body: 'Bundles, gift guides, free shipping. Swap ideas here.',
      },
      {
        title: 'Do you run sales or discount codes, and do they work?',
        body: 'Tell us what happened the last time you tried one.',
      },
    ],
  },
  {
    title: 'Shipping and Packaging',
    description: 'Boxes, labels, costs and the small touches buyers remember.',
    tags: ['#shipping'],
    threads: [
      {
        title: 'Favourite eco-friendly packaging supplier?',
        body: 'Share where you buy, and roughly what it costs you.',
      },
      {
        title: 'What do you do when a package gets lost in the mail?',
        body: 'How you handle it with the buyer and with the carrier.',
      },
    ],
  },
  {
    title: 'Wins and Shoutouts',
    description: 'Celebrate each other.',
    tags: ['#wins'],
    threads: [
      {
        title: 'Share a win from this week, big or small',
        body: 'A first sale, a great review, a finished batch. We want to hear it.',
      },
      {
        title: 'Shout out a business that helped or inspired you',
        body: 'Tag them with Tag someone so they see it.',
      },
    ],
  },
];

/** Which starter forums are not there yet, by title, ignoring case. Pure. */
export function forumsToCreate(
  existingTitles: string[],
  starters: StarterForum[] = STARTER_FORUMS,
): StarterForum[] {
  const taken = new Set(existingTitles.map((t) => t.trim().toLowerCase()));
  return starters.filter((f) => !taken.has(f.title.trim().toLowerCase()));
}

export interface SeedReport {
  created: string[];
  skipped: string[];
  threads: number;
}

/**
 * Creates every starter forum that is missing, with its threads, as `uid`.
 *
 * The same fields the app writes, so the triggers count them exactly as if
 * they had been typed in: the membership doc moves memberCount to 1 and each
 * thread moves threadCount. A new forum has no other members yet, so no one
 * is pushed about these threads.
 */
export async function seedStarterForums(uid: string): Promise<SeedReport> {
  const db = getFirestore();
  const existing = await db.collection('forums').select('title').get();
  const titles = existing.docs.map((d) => String(d.data().title ?? ''));
  const missing = forumsToCreate(titles);
  const report: SeedReport = {
    created: [],
    skipped: STARTER_FORUMS.filter((f) => !missing.includes(f)).map((f) => f.title),
    threads: 0,
  };

  for (const forum of missing) {
    const forumRef = db.collection('forums').doc();
    const batch = db.batch();
    batch.set(forumRef, {
      title: forum.title,
      description: forum.description,
      tags: forum.tags,
      createdBy: uid,
      memberCount: 0,
      threadCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.set(forumRef.collection('members').doc(uid), {
      joinedAt: FieldValue.serverTimestamp(),
    });
    for (const thread of forum.threads) {
      batch.set(db.collection('threads').doc(), {
        forumId: forumRef.id,
        authorId: uid,
        title: thread.title,
        body: thread.body,
        commentCount: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      report.threads += 1;
    }
    await batch.commit();
    report.created.push(forum.title);
  }
  return report;
}
