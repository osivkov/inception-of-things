import test from 'node:test';
import assert from 'node:assert/strict';
import { Reminder } from '../dist/notifications.mjs';

function fixture(permission = 'default') {
  const sent = [];
  let requests = 0;
  class Notification {
    static permission = permission;
    static async requestPermission() { requests++; return Notification.permission; }
    constructor(title, options) { sent.push({ title, options }); }
    close() {}
  }
  const env = { isSecureContext: true, Notification, navigator: {}, focus() {} };
  return { env, sent, requests: () => requests, reminder: new Reminder(env) };
}

test('initialization, state checks and completion never request permission', async () => {
  const f = fixture();
  assert.equal(f.reminder.state(), 'default');
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'page-only');
  assert.equal(f.requests(), 0); assert.equal(f.sent.length, 0);
});

test('explicit enable requests permission once and respects dismissal', async () => {
  const f = fixture();
  assert.equal(await f.reminder.enable(), 'default');
  assert.equal(f.requests(), 1);
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'page-only');
});

test('denied permission never prompts again and always uses the page fallback', async () => {
  const f = fixture('denied');
  assert.equal(await f.reminder.enable(), 'denied');
  assert.equal(await f.reminder.send('one', 'Break finished', 'Start focus'), 'page-only');
  assert.equal(f.requests(), 0); assert.equal(f.sent.length, 0);
});

test('granted permission sends once per completion ID, including concurrent calls', async () => {
  const f = fixture('granted');
  assert.deepEqual(await Promise.all([
    f.reminder.send('same', 'Focus finished', 'Take a break'),
    f.reminder.send('same', 'Focus finished', 'Take a break'),
  ]), ['sent', 'duplicate']);
  assert.equal(f.sent.length, 1);
  await f.reminder.send('next', 'Short break finished', 'Start focus');
  assert.equal(f.sent.length, 2);
});

test('browser permission changes are authoritative, without a stale local preference', async () => {
  const f = fixture('granted');
  f.env.Notification.permission = 'denied';
  assert.equal(f.reminder.state(), 'denied');
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'page-only');
  assert.equal(f.sent.length, 0);
});

test('secure context and API availability are checked independently', async () => {
  const f = fixture('granted');
  f.env.isSecureContext = false;
  assert.equal(f.reminder.state(), 'insecure');
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'page-only');
  f.env.isSecureContext = true; delete f.env.Notification;
  assert.equal(f.reminder.state(), 'unavailable');
  assert.equal(await f.reminder.enable(), 'unavailable');
  assert.equal(f.requests(), 0);
});

test('constructor failure is caught and does not produce duplicate attempts', async () => {
  const f = fixture('granted');
  f.env.Notification = class {
    static permission = 'granted'; static requestPermission() {}
    constructor() { throw new TypeError('Unsupported'); }
  };
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'failed');
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'duplicate');
});

test('mobile worker display is used if the constructor fails', async () => {
  const f = fixture('granted'); let workerCalls = 0;
  f.env.Notification = class {
    static permission = 'granted'; static requestPermission() {}
    constructor() { throw new TypeError('Use a worker'); }
  };
  const worker = { active: true, async showNotification() { workerCalls++; } };
  f.env.setTimeout = () => {};
  f.env.navigator.serviceWorker = { register: async () => worker, ready: Promise.resolve(worker) };
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'sent');
  assert.equal(workerCalls, 1);
});

test('worker failure is caught and the completion stays page-only', async () => {
  const f = fixture('granted');
  f.env.Notification = class {
    static permission = 'granted'; static requestPermission() {}
    constructor() { throw new TypeError('Use a worker'); }
  };
  const worker = { active: true, async showNotification() { throw Error('OS unavailable'); } };
  f.env.setTimeout = () => {};
  f.env.navigator.serviceWorker = { register: async () => worker, ready: Promise.resolve(worker) };
  assert.equal(await f.reminder.send('one', 'Focus finished', 'Take a break'), 'failed');
});
