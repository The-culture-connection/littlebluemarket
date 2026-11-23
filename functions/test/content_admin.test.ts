import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { matchesWords, parseContentPath } from '../src/content_admin.ts';

test('the delete tool names only the things it is meant to delete', () => {
  assert.equal(parseContentPath('posts/abc')?.kind, 'post');
  assert.equal(parseContentPath('posts/abc/comments/c1')?.kind, 'postComment');
  assert.equal(parseContentPath('threads/t1')?.kind, 'thread');
  assert.equal(parseContentPath('threads/t1/comments/c1')?.kind, 'threadComment');
  assert.equal(parseContentPath('directoryProducts/p1')?.kind, 'directoryProduct');
  assert.equal(parseContentPath('chatroom/m1')?.kind, 'chat');
  // Never a person, an order, a seller grant or the admin list.
  for (const bad of ['users/u1', 'orders/o1', 'sellers/u1', '_internal/admins', 'forums/f1', 'catalog/p1',
    'posts', 'posts/', 'posts/a/likes/u1', 'posts/../users', 'threads/t1/comments', '', null, 42]) {
    assert.equal(parseContentPath(bad), null, String(bad));
  }
});

test('word search needs every word, ignores case and punctuation', () => {
  const title = 'Favorite eco-friendly packaging supplier?';
  assert.equal(matchesWords(title, 'favorite eco-friendly packaging supplier?'), true);
  assert.equal(matchesWords(title, 'PACKAGING supplier'), true);
  assert.equal(matchesWords(title, 'packaging glitter'), false);
  assert.equal(matchesWords(title, '   '), false);
});
