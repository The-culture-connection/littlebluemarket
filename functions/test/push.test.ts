import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { isAudience, shouldNotifyAtAll, shouldPrune, shouldPush, titleFor, topicTarget } from '../src/push.ts';

test('an audience is a topic, except buyers, which is "everyone who is not a seller"', () => {
  assert.deepEqual(topicTarget('all'), { topic: 'all' });
  assert.deepEqual(topicTarget('sellers'), { topic: 'sellers' });
  assert.deepEqual(topicTarget('directory'), { topic: 'directory' });
  assert.deepEqual(topicTarget('buyers'), { condition: "'all' in topics && !('sellers' in topics)" });
  assert.equal(isAudience('buyers'), true);
  assert.equal(isAudience('everyone'), false);
  assert.equal(isAudience(undefined), false);
});

test('every switch defaults to on, and off means off for exactly that kind', () => {
  assert.equal(shouldPush(undefined, { type: 'mention' }), true);
  assert.equal(shouldPush({}, { type: 'newProduct' }), true);
  assert.equal(shouldPush({ comments: false }, { type: 'comment' }), false);
  assert.equal(shouldPush({ comments: false }, { type: 'mention' }), true);
  assert.equal(shouldPush({ forums: false }, { type: 'forumThread' }), false);
  assert.equal(shouldPush({ forums: false }, { type: 'forumReply' }), false);
  assert.equal(shouldPush({ reviews: false }, { type: 'review' }), false);
  assert.equal(shouldPush({ announcements: false }, { type: 'announcement' }), false);
  // The test push ignores every switch: it exists to prove the channel.
  assert.equal(shouldPush({ mentions: false, comments: false }, { type: 'test' }), true);
});

test('a muted forum silences both the push and the bell; other forums are untouched', () => {
  const prefs = { mutedForums: ['f1'] };
  assert.equal(shouldPush(prefs, { type: 'forumThread', forumId: 'f1' }), false);
  assert.equal(shouldNotifyAtAll(prefs, { type: 'forumReply', forumId: 'f1' }), false);
  assert.equal(shouldPush(prefs, { type: 'forumThread', forumId: 'f2' }), true);
  assert.equal(shouldNotifyAtAll(prefs, { type: 'mention' }), true);
});

test('only the codes that mean "dead token" prune a device', () => {
  assert.equal(shouldPrune('messaging/registration-token-not-registered'), true);
  assert.equal(shouldPrune('messaging/invalid-registration-token'), true);
  assert.equal(shouldPrune('messaging/invalid-argument'), true);
  assert.equal(shouldPrune('messaging/internal-error'), false);
  assert.equal(shouldPrune('messaging/quota-exceeded'), false);
  assert.equal(shouldPrune(undefined), false);
});

test('titles name the person, except announcements, which carry their own', () => {
  assert.equal(titleFor('mention', 'Kali'), 'Kali mentioned you');
  assert.equal(titleFor('comment', ''), 'Someone commented on your post');
  assert.equal(titleFor('review', 'Dee'), 'Dee reviewed your product');
  assert.equal(titleFor('forumThread', 'Dee'), 'Dee started a thread');
  assert.equal(titleFor('forumReply', 'Dee'), 'Dee replied');
  assert.equal(titleFor('newProduct', 'Gwynstone'), 'New from Gwynstone');
  assert.equal(titleFor('announcement', '', 'Hello from Little Blue Market'), 'Hello from Little Blue Market');
  assert.equal(titleFor('announcement', ''), 'Little Blue Market');
  assert.equal(titleFor('test', ''), 'Little Blue Market');
});
