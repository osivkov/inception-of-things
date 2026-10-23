import test from 'node:test';
import assert from 'node:assert/strict';
import { Timer } from '../dist/timer.mjs';

function fixture() {
  let now = 0;
  const ended = [];
  const timer = new Timer({ now: () => now, onComplete: event => ended.push(event) });
  return { timer, ended, advance: ms => { now += ms; } };
}

test('focus supports 15, 25 and 45 minutes; both break lengths are valid', () => {
  const { timer } = fixture();
  for (const minutes of [15, 25, 45]) {
    timer.reset('focus', minutes * 60);
    assert.equal(timer.remaining, minutes * 60);
  }
  timer.reset('short', 300); assert.equal(timer.remaining, 300);
  timer.reset('long', 900); assert.equal(timer.remaining, 900);
});

test('missed background ticks use the deadline, not interval count', () => {
  const { timer, ended, advance } = fixture();
  timer.start();
  advance(10 * 60 * 1000 + 150);
  timer.tick();
  assert.equal(timer.remaining, 900);
  advance(20 * 60 * 1000);
  timer.tick();
  assert.equal(timer.remaining, 0);
  assert.equal(ended.length, 1);
  assert.equal(ended[0].mode, 'focus');
});

test('pause keeps millisecond precision and time does not pass while paused', () => {
  const { timer, advance } = fixture();
  timer.start(); advance(1250); timer.pause();
  const remaining = timer.remainingMs;
  advance(60000); timer.tick();
  assert.equal(timer.remainingMs, remaining);
  timer.start(); advance(750); timer.tick();
  assert.equal(timer.remainingMs, 1498000);
});

test('returning to a finished tab, pausing at zero and clicking start cannot complete twice', () => {
  const { timer, ended, advance } = fixture();
  timer.reset('short', 300); timer.start(); advance(300000);
  timer.pause(); timer.tick(); timer.start(); timer.tick();
  assert.equal(ended.length, 1);
  assert.equal(timer.finished, true);
  assert.equal(timer.running, false);
});

test('reset invalidates the old period and a new session completes once', () => {
  const { timer, ended, advance } = fixture();
  timer.start(); const old = timer.id;
  advance(1400000); timer.reset('long', 900);
  timer.tick(); assert.equal(ended.length, 0);
  assert.notEqual(timer.id, old);
  timer.start(); advance(900000); timer.tick(); timer.tick();
  assert.equal(ended.length, 1);
  assert.equal(ended[0].mode, 'long');
});
