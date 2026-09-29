import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import {
  DEV_PROJECT,
  diagTopic,
  isDiagStep,
  quietWindow,
  requireDevProject,
} from '../src/diagnostics_notify.ts';
import { announcementMessage, isQuietHours, topicTarget } from '../src/push.ts';

/**
 * The Diagnostics delivery suite's backend. What matters most here is that
 * the announcement it sends is the real one, so a pass on the phone means
 * the real announcement would have arrived too.
 */

test('an announcement on the wire is exactly the shape real announcements have always had', () => {
  const message = announcementMessage(topicTarget('all'), {
    title: 'Town hall',
    body: 'Tonight at 7',
    route: '/community',
    announcementId: 'a1',
  });
  assert.deepEqual(message, {
    topic: 'all',
    notification: { title: 'Town hall', body: 'Tonight at 7' },
    data: { route: '/community', type: 'announcement', announcementId: 'a1' },
    android: {
      priority: 'high',
      notification: { channelId: 'lbm_default', icon: 'ic_stat_lbm', color: '#70A0D0' },
    },
    apns: { payload: { aps: { sound: 'default' } } },
  });
});

test('the diagnostic announcement differs only in where it goes', () => {
  const real = announcementMessage(topicTarget('all'), { title: 't', body: 'b', route: '/r', announcementId: 'x' });
  const diag = announcementMessage({ topic: diagTopic('abc') }, { title: 't', body: 'b', route: '/r', announcementId: 'x' });
  const { topic: _a, ...realRest } = real as unknown as Record<string, unknown>;
  const { topic: _b, ...diagRest } = diag as unknown as Record<string, unknown>;
  assert.deepEqual(diagRest, realRest);
  assert.equal((diag as unknown as { topic: string }).topic, 'diag_abc');
});

test('the private topic is one FCM accepts, whatever the uid', () => {
  assert.equal(diagTopic('Ab_9-x'), 'diag_Ab_9-x');
  assert.match(diagTopic('we!rd/uid'), /^[A-Za-z0-9_.~-]+$/);
});

test('it refuses every project but dev', () => {
  assert.doesNotThrow(() => requireDevProject(DEV_PROJECT));
  assert.throws(() => requireDevProject('little-blue-cart-prod'), /dev project/);
  assert.throws(() => requireDevProject(''), /dev project/);
});

test('only the known steps run', () => {
  assert.equal(isDiagStep('announcement'), true);
  assert.equal(isDiagStep('restore'), true);
  assert.equal(isDiagStep('deleteEverything'), false);
  assert.equal(isDiagStep(undefined), false);
});

test('the quiet windows it sets are around now, and well away from now', () => {
  const now = new Date('2026-09-28T18:00:00Z');
  assert.equal(isQuietHours(quietWindow(now, true), now), true);
  assert.equal(isQuietHours(quietWindow(now, false), now), false);
  // Near midnight the window wraps, and still means what it says.
  const late = new Date('2026-09-29T03:50:00Z');
  assert.equal(isQuietHours(quietWindow(late, true), late), true);
  assert.equal(isQuietHours(quietWindow(late, false), late), false);
});
