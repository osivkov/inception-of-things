import { Timer } from './timer.mjs';
import { Reminder } from './notifications.mjs';

const $ = id => document.getElementById(id);
const modeButtons = [...document.querySelectorAll('[data-mode]')];
const minuteButtons = [...document.querySelectorAll('[data-minutes]')];
const reminder = new Reminder(window);
let storageWarning = false;
let toastTimeout;
let pageLoaded = false;
let sessionTask = null;
let selectedId = '';
let release;
let tasks = [];
let focusMinutes = 25;
let sessions;
let timer;
let notificationBusy = false;
let testSequence = 0;
const pageId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
const today = () => new Date().toLocaleDateString('en-CA');

function toast(message) {
  clearTimeout(toastTimeout);
  $('toast').textContent = message;
  $('toast').classList.add('show');
  toastTimeout = setTimeout(() => $('toast').classList.remove('show'), 5000);
}

function storageError() {
  if (storageWarning) return;
  storageWarning = true;
  $('storage-message').hidden = false;
}

function read(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? fallback : JSON.parse(raw);
  } catch { storageError(); return fallback; }
}

function write(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); }
  catch { storageError(); }
}

function dailyCount(value) {
  return value && value.date === today() && Number.isSafeInteger(value.count) && value.count >= 0
    ? value : { date: today(), count: 0 };
}

function currentTask() { return tasks.find(task => task.id === selectedId && !task.done); }
function locked() { return timer.mode === 'focus' && timer.started && !timer.finished; }
function duration(mode) { return (mode === 'focus' ? focusMinutes : mode === 'short' ? 5 : 15) * 60; }

function updateReminderUI() {
  const state = reminder.state();
  const descriptions = {
    default: 'Get a browser notification when focus time or a break ends.',
    granted: 'Browser notifications are allowed. Keep this page open while the timer runs.',
    denied: 'Notifications are blocked. You can allow them in your browser’s site settings. Session endings will still appear here.',
    unavailable: 'This browser cannot show notifications here. Session endings will appear on this page.',
    insecure: 'Browser notifications need HTTPS or a supported localhost address. Session endings will appear on this page.',
  };
  $('notification-status').textContent = descriptions[state] || descriptions.unavailable;
  $('enable-notifications').hidden = state !== 'default';
  $('enable-notifications').disabled = notificationBusy;
  $('test-notification').hidden = state !== 'granted';
  $('test-notification').disabled = notificationBusy;
  $('notification-state').textContent = {
    default: 'Off', granted: 'Allowed', denied: 'Blocked', unavailable: 'Unavailable', insecure: 'Page only',
  }[state] || 'Unavailable';
}

$('enable-notifications').onclick = async () => {
  if (notificationBusy) return;
  notificationBusy = true;
  updateReminderUI();
  try { await reminder.enable(); }
  catch { toast('Notifications could not be enabled. Session endings will still appear here.'); }
  finally { notificationBusy = false; updateReminderUI(); }
};

$('test-notification').onclick = async () => {
  if (notificationBusy) return;
  notificationBusy = true;
  updateReminderUI();
  try {
    const result = await reminder.send(`${pageId}-test-${++testSequence}`, 'One more cup', 'Notifications are ready. Your next session can begin.');
    toast(result === 'sent' ? 'Test notification sent. Check your system’s notification settings if it did not appear.' : 'Your browser could not show the test. Session endings will still appear here.');
  } finally { notificationBusy = false; updateReminderUI(); }
};

function updatePlan() {
  $('focus-task').disabled = locked();
  minuteButtons.forEach(button => {
    button.setAttribute('aria-pressed', String(Number(button.dataset.minutes) === focusMinutes));
    button.disabled = locked();
  });
  document.querySelectorAll('.choose-task').forEach(button => { button.disabled = locked(); });
  $('plan-hint').textContent = locked()
    ? 'This session is set. Reset to change the task or time.'
    : 'Choose a task, or focus without one.';
}

function renderTasks(focusTarget = null) {
  const list = $('tasks');
  list.replaceChildren();
  const select = $('focus-task');
  select.replaceChildren(new Option('Focus without a task', ''));
  tasks.forEach(task => {
    if (!task.done) select.append(new Option(task.text, task.id));
    const li = document.createElement('li');
    li.classList.toggle('done', task.done);
    li.classList.toggle('active-task', task.id === selectedId && !task.done);
    const check = document.createElement('input');
    check.type = 'checkbox';
    check.checked = task.done;
    check.id = `check-${task.id}`;
    check.setAttribute('aria-label', `Mark ${task.text} ${task.done ? 'unfinished' : 'done'}`);
    check.onchange = () => {
      task.done = check.checked;
      if (task.done && selectedId === task.id) selectedId = '';
      saveTasks(check.id);
    };
    const text = document.createElement('label');
    text.htmlFor = check.id;
    text.textContent = task.text;
    li.append(check, text);
    if (!task.done) {
      const choose = document.createElement('button');
      choose.type = 'button';
      choose.id = `choose-${task.id}`;
      choose.className = 'choose-task';
      choose.textContent = selectedId === task.id ? 'Selected' : 'Focus';
      choose.setAttribute('aria-pressed', String(selectedId === task.id));
      choose.setAttribute('aria-label', `Focus on ${task.text}`);
      choose.onclick = () => {
        if (locked()) return;
        selectedId = task.id;
        setMode('focus');
        $('start').focus();
      };
      li.append(choose);
    }
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'remove-task';
    remove.textContent = '×';
    remove.setAttribute('aria-label', `Delete ${task.text}`);
    remove.onclick = () => {
      tasks = tasks.filter(item => item.id !== task.id);
      if (selectedId === task.id) selectedId = '';
      saveTasks();
      $('task-input').focus();
    };
    li.append(remove);
    list.append(li);
  });
  select.value = currentTask() ? selectedId : '';
  $('count').textContent = `${tasks.filter(task => task.done).length} / ${tasks.length}`;
  $('empty').hidden = tasks.length > 0;
  $('clear').disabled = !tasks.some(task => task.done);
  updatePlan();
  updateCompletion();
  if (focusTarget) $(focusTarget)?.focus();
}

function saveTasks(focusTarget) {
  write('cup-tasks', tasks);
  renderTasks(focusTarget);
}

function updateCompletion() {
  if (!timer.finished) return;
  const unfinished = tasks.some(task => task.id === sessionTask?.id && !task.done);
  $('finish-task').hidden = timer.mode !== 'focus' || !unfinished;
}

function renderTimer() {
  const seconds = timer.remaining;
  $('time').textContent = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
  document.title = `${timer.finished ? 'Session complete · ' : timer.running ? `${$('time').textContent} · ` : ''}One more cup`;
  $('dial').style.setProperty('--progress', `${360 * timer.progress}deg`);
  $('start-label').textContent = timer.running ? 'Pause' : timer.started ? 'Resume' : 'Start';
  $('start-symbol').textContent = timer.running ? 'Ⅱ' : '↗';
  $('state').textContent = timer.finished ? 'session complete' : timer.running ? 'in progress' : timer.started ? 'paused' : 'ready when you are';
  $('focus-plan').hidden = timer.mode !== 'focus' || timer.finished;
  $('break-note').hidden = timer.mode === 'focus' || timer.finished;
  $('dial').hidden = timer.finished;
  $('timer-controls').hidden = timer.finished;
  $('finish-card').hidden = !timer.finished;
  $('kicker').textContent = timer.mode === 'focus' ? 'ONE THING AT A TIME' : 'TAKE A BREAK';
  $('timer-note').textContent = timer.mode === 'focus' ? 'Everything else can wait' : 'Stretch, get some water, look away';
  modeButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.mode === timer.mode)));
  updatePlan();
}

function setMode(mode) {
  if (!['focus', 'short', 'long'].includes(mode)) return;
  timer.reset(mode, duration(mode));
  sessionTask = null;
  renderTimer();
  renderTasks();
}

async function complete(period) {
  if (period.mode === 'focus') {
    sessions = dailyCount(read('cup-sessions', sessions));
    sessions.count++;
    write('cup-sessions', sessions);
    $('sessions').textContent = sessions.count;
  }
  const title = period.mode === 'focus' ? 'Focus time finished' : period.mode === 'short' ? 'Short break finished' : 'Long break finished';
  const next = period.mode === 'focus' ? 'Take a 5-minute break when you’re ready.' : 'Choose a task and start your next focus session.';
  $('finish-title').textContent = title;
  $('finish-copy').textContent = period.mode === 'focus' && sessionTask
    ? `You spent ${period.seconds / 60} minutes on “${sessionTask.text}”. Mark it done if it’s finished. ${next}`
    : next;
  $('finish-primary').textContent = period.mode === 'focus' ? 'Start a 5 min break' : 'Plan the next session';
  $('finish-delivery').textContent = 'This session has ended. The timer is stopped.';
  renderTimer();
  updateCompletion();
  $('completion-announcement').textContent = `${title}. ${next}`;
  if (!document.hidden) $('finish-card').focus();
  updateReminderUI();
  const result = await reminder.send(`${pageId}-${period.id}`, title, next);
  // Do not alter a new session after a slower mobile notification attempt.
  if (timer.id === period.id && timer.finished && result === 'failed') {
    $('finish-delivery').textContent = 'Your browser could not show a system notification. Your session has ended here.';
  }
}

function bindApp() {
  $('task-form').onsubmit = event => {
    event.preventDefault();
    const input = $('task-input');
    const text = input.value.trim();
    if (!text) { input.setCustomValidity('Enter a task first.'); input.reportValidity(); return; }
    if (tasks.length >= 100) { toast('Your list is full. Remove a task before adding another.'); return; }
    const task = { id: `task-${Date.now()}-${Math.random().toString(36).slice(2)}`, text: text.slice(0, 100), done: false };
    tasks.push(task);
    if (!currentTask() && !locked()) selectedId = task.id;
    input.value = '';
    saveTasks();
    input.focus();
  };
  $('task-input').oninput = () => $('task-input').setCustomValidity('');
  $('clear').onclick = () => {
    tasks = tasks.filter(task => !task.done);
    saveTasks();
    $('task-input').focus();
  };
  $('focus-task').onchange = () => {
    if (locked()) return;
    selectedId = $('focus-task').value;
    renderTasks('focus-task');
  };
  $('start').onclick = () => {
    if (timer.running) timer.pause();
    else {
      if (timer.mode === 'focus' && !timer.started) {
        const task = currentTask();
        sessionTask = task ? { id: task.id, text: task.text } : null;
      }
      timer.start();
    }
    renderTimer();
  };
  $('reset').onclick = () => { setMode(timer.mode); $('start').focus(); };
  $('finish-primary').onclick = () => {
    const next = timer.mode === 'focus' ? 'short' : 'focus';
    setMode(next);
    if (next === 'short') { timer.start(); renderTimer(); $('start').focus(); }
    else $('focus-task').focus();
  };
  $('finish-task').onclick = () => {
    const task = tasks.find(item => item.id === sessionTask?.id);
    if (!task || task.done) return;
    task.done = true;
    if (selectedId === task.id) selectedId = '';
    saveTasks();
    toast('Task completed.');
    $('finish-primary').focus();
  };
  modeButtons.forEach(button => { button.onclick = () => setMode(button.dataset.mode); });
  minuteButtons.forEach(button => {
    button.onclick = () => {
      if (locked()) return;
      focusMinutes = Number(button.dataset.minutes);
      write('cup-focus-minutes', focusMinutes);
      setMode('focus');
    };
  });
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) { timer.tick(); renderTimer(); updateReminderUI(); }
  });
  window.addEventListener('focus', () => { timer.tick(); renderTimer(); updateReminderUI(); });
  setInterval(() => { timer.tick(); renderTimer(); }, 250);
}

async function loadApp() {
  $('load-error').hidden = true;
  try {
    const response = await fetch('./version.json', { cache: 'no-store' });
    if (!response.ok) throw new Error('Release unavailable');
    release = await response.json();
    if (!['v1', 'v2'].includes(release.version)) throw new Error('Unknown release');
  } catch {
    $('release').textContent = 'unavailable';
    $('load-error').hidden = false;
    return;
  }
  if (pageLoaded) return;
  pageLoaded = true;
  document.body.classList.toggle('v2', release.version === 'v2');
  $('release').textContent = `${release.version} / ${release.version === 'v2' ? 'slow roast' : 'first brew'}`;
  $('edition').textContent = release.version === 'v2' ? 'SLOW ROAST / 002' : 'FIRST BREW / 001';
  // Both releases provide the full focus/break/task/notification flow. They differ only visually.
  const storedMinutes = read('cup-focus-minutes', 25);
  focusMinutes = [15, 25, 45].includes(storedMinutes) ? storedMinutes : 25;
  const storedTasks = read('cup-tasks', []);
  tasks = (Array.isArray(storedTasks) ? storedTasks : [])
    .filter(task => task && typeof task.text === 'string' && task.text.trim())
    .slice(0, 100)
    .map((task, index) => ({
      id: `task-${index}-${Math.random().toString(36).slice(2)}`,
      text: task.text.trim().slice(0, 100), done: task.done === true,
    }));
  selectedId = tasks.find(task => !task.done)?.id || '';
  sessions = dailyCount(read('cup-sessions', null));
  $('sessions').textContent = sessions.count;
  timer = new Timer({ onComplete: complete });
  timer.reset('focus', duration('focus'));
  bindApp();
  $('app-controls').disabled = false;
  renderTasks();
  renderTimer();
}

$('retry-load').onclick = loadApp;
updateReminderUI();
// An existing grant may need a worker on mobile; this never prompts for permission.
if (reminder.state() === 'granted') void reminder.prepare();
void loadApp();
