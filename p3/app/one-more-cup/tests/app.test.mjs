// Lightweight application integration tests: the real entry point with a small DOM fixture.
// These complement real-browser checks.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

async function appFixture({ version = 'v1', permission = 'default', secure = true, brokenVersion = false, brokenStorage = false } = {}) {
  const elements = new Map(), created = [], listeners = {}, storage = new Map();
  let now = 0, interval, permissions = 0;
  const notifications = [];
  class Element {
    constructor(tag = '') {
      this.tag = tag; this.children = []; this.dataset = {}; this.value = ''; this.hidden = false;
      this.disabled = false; this.textContent = ''; this.style = { setProperty() {} };
      this.classList = { toggle() {}, add() {}, remove() {} };
      created.push(this);
    }
    set id(value) { this._id = value; elements.set(value, this); }
    get id() { return this._id; }
    append(...items) { this.children.push(...items); }
    replaceChildren(...items) { this.children = items; }
    setAttribute(key, value) { this[key] = value; }
    focus() { document.activeElement = this; }
    setCustomValidity(message) { this.validityMessage = message; }
    reportValidity() { return !this.validityMessage; }
  }
  const get = id => {
    if (!elements.has(id)) { const e = new Element(); e.id = id; }
    return elements.get(id);
  };
  // Initial disabled state mirrors the HTML.
  get('app-controls').disabled = true;
  const modes = ['focus', 'short', 'long'].map(mode => { const e = new Element(); e.dataset.mode = mode; return e; });
  const minutes = [15, 25, 45].map(n => { const e = new Element(); e.dataset.minutes = String(n); return e; });
  const document = {
    hidden: false, body: new Element(), getElementById: get,
    createElement: tag => new Element(tag),
    querySelectorAll: selector => selector === '[data-mode]' ? modes : selector === '[data-minutes]' ? minutes : created.filter(e => e.className === 'choose-task'),
    addEventListener: (name, fn) => { listeners[name] = fn; },
  };
  class Notification {
    static permission = permission;
    static async requestPermission() { permissions++; return Notification.permission; }
    constructor(title, options) { notifications.push({ title, options }); }
    close() {}
  }
  const actualDate = globalThis.Date;
  class ClockDate extends actualDate { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } }
  const before = new Map();
  const replace = (key, value) => { before.set(key, globalThis[key]); globalThis[key] = value; };
  replace('document', document);
  replace('window', { Notification, isSecureContext: secure, navigator: {}, setTimeout() {}, addEventListener(name, fn) { listeners[name] = fn; } });
  replace('localStorage', { getItem(key) { if (brokenStorage) throw Error('Blocked'); return storage.get(key) ?? null; }, setItem(key, value) { if (brokenStorage) throw Error('Blocked'); storage.set(key, value); } });
  replace('Option', class extends Element { constructor(text, value) { super('option'); this.textContent = text; this.value = value; } });
  replace('fetch', async () => ({ ok: !brokenVersion, json: async () => ({ version }) }));
  replace('Date', ClockDate);
  replace('setInterval', fn => { interval = fn; });
  replace('setTimeout', () => 0);
  replace('clearTimeout', () => {});
  let source = await readFile(new URL('../dist/app.js', import.meta.url), 'utf8');
  source = source.replace("'./timer.mjs'", JSON.stringify(new URL('../dist/timer.mjs', import.meta.url).href));
  source = source.replace("'./notifications.mjs'", JSON.stringify(new URL('../dist/notifications.mjs', import.meta.url).href));
  await import(`data:text/javascript;base64,${Buffer.from(source + '\n// ' + Math.random()).toString('base64')}`);
  await new Promise(resolve => setImmediate(resolve));
  return { get, modes, minutes, storage, document, listeners, notifications,
    requests: () => permissions,
    async advance(ms) { now += ms; interval?.(); await new Promise(resolve => setImmediate(resolve)); },
    add(text) { get('task-input').value = text; get('task-form').onsubmit({ preventDefault() {} }); },
    restore() { for (const [key, value] of before) globalThis[key] = value; },
  };
}

for (const version of ['v1', 'v2']) {
  test(`${version}: complete task -> focus -> completion -> break -> plan next session`, async () => {
    const f = await appFixture({ version, permission: 'granted' });
    try {
      assert.equal(f.get('app-controls').disabled, false);
      assert.ok(f.get('release').textContent.startsWith(version));
      f.add('Review the deployment');
      f.minutes[0].onclick();
      f.get('start').onclick();
      assert.equal(f.get('focus-task').disabled, true);
      f.document.hidden = true;
      await f.advance(900001);
      assert.equal(f.get('finish-card').hidden, false);
      assert.ok(f.get('finish-copy').textContent.includes('Review the deployment'));
      assert.equal(f.notifications.length, 1);
      f.document.hidden = false; f.listeners.visibilitychange();
      await f.advance(1000);
      assert.equal(f.notifications.length, 1);
      f.get('finish-task').onclick();
      assert.equal(JSON.parse(f.storage.get('cup-tasks'))[0].done, true);
      f.get('finish-primary').onclick();
      assert.equal(f.get('time').textContent, '05:00');
      await f.advance(300001);
      assert.equal(f.get('finish-title').textContent, 'Short break finished');
      assert.equal(f.notifications.length, 2);
      f.get('finish-primary').onclick();
      assert.equal(f.get('time').textContent, '15:00');
      f.modes[2].onclick();
      assert.equal(f.get('time').textContent, '15:00');
    } finally { f.restore(); }
  });
}

test('denied browser permission shows a completion card without another prompt', async () => {
  const f = await appFixture({ permission: 'denied' });
  try {
    assert.equal(f.get('notification-state').textContent, 'Blocked');
    f.modes[1].onclick(); f.get('start').onclick(); await f.advance(300000);
    assert.equal(f.get('finish-card').hidden, false);
    assert.equal(f.get('finish-title').textContent, 'Short break finished');
    assert.equal(f.requests(), 0); assert.equal(f.notifications.length, 0);
  } finally { f.restore(); }
});

test('default permission requests only after clicking Enable notifications', async () => {
  const f = await appFixture();
  try {
    assert.equal(f.requests(), 0);
    await f.get('enable-notifications').onclick();
    assert.equal(f.requests(), 1);
    assert.equal(f.get('notification-state').textContent, 'Off');
  } finally { f.restore(); }
});

test('unavailable release leaves controls disabled and exposes retry', async () => {
  const f = await appFixture({ brokenVersion: true });
  try { assert.equal(f.get('load-error').hidden, false); assert.equal(f.get('app-controls').disabled, true); }
  finally { f.restore(); }
});

test('blocked storage warns without breaking task entry, safe text or the timer', async () => {
  const f = await appFixture({ brokenStorage: true, secure: false });
  try {
    assert.equal(f.get('storage-message').hidden, false);
    assert.equal(f.get('notification-state').textContent, 'Page only');
    f.add('<img src=x onerror=alert(1)>');
    const label = f.get('tasks').children[0].children[1];
    assert.equal(label.tag, 'label'); assert.equal(label.textContent, '<img src=x onerror=alert(1)>');
    f.get('start').onclick(); await f.advance(1000); assert.equal(f.get('time').textContent, '24:59');
  } finally { f.restore(); }
});
