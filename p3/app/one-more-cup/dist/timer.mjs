// Clock-based timer. A delayed tick completes a period once, without replaying missed ticks.
export class Timer {
  constructor({ now = () => Date.now(), onComplete = () => {} } = {}) {
    this.now = now;
    this.onComplete = onComplete;
    this.sequence = 0;
    this.reset('focus', 25 * 60);
  }

  reset(mode, seconds) {
    if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('Invalid duration');
    this.mode = mode;
    this.totalMs = seconds * 1000;
    this.remainingMs = this.totalMs;
    this.deadline = 0;
    this.running = false;
    this.finished = false;
    this.id = ++this.sequence;
  }

  start() {
    if (this.finished || this.running) return;
    this.deadline = this.now() + this.remainingMs;
    this.running = true;
  }

  pause() {
    this.tick();
    this.running = false;
  }

  tick() {
    if (!this.running || this.finished) return;
    this.remainingMs = Math.max(0, this.deadline - this.now());
    if (this.remainingMs === 0) {
      // Set the guard before calling any UI or asynchronous notification code.
      this.running = false;
      this.finished = true;
      this.onComplete({ id: this.id, mode: this.mode, seconds: this.totalMs / 1000 });
    }
  }

  get remaining() { return Math.ceil(this.remainingMs / 1000); }
  get started() { return this.running || this.remainingMs < this.totalMs; }
  get progress() { return 1 - this.remainingMs / this.totalMs; }
}
