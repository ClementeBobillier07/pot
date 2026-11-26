import { test } from 'node:test';
import assert from 'node:assert/strict';
import { treeProgress } from '../lib/trees';

test('tree progress is hidden until configured', () => {
  assert.equal(treeProgress(1234, 0), null);
});
test('tree progress counts whole trees and the distance to the next', () => {
  assert.deepEqual(treeProgress(2350, 1000), { trees: 2, toNext: 650, fraction: 0.35 });
  assert.deepEqual(treeProgress(0, 1000), { trees: 0, toNext: 1000, fraction: 0 });
  assert.equal(treeProgress(-1, 1000), null);
});
