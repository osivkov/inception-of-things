export class Reminder {
  constructor(env = globalThis) {
    this.env = env;
    this.sent = new Set();
    this.registration = null;
    this.preparing = null;
  }

  state() {
    if (!this.env.isSecureContext) return 'insecure';
    if (!this.env.Notification || typeof this.env.Notification.requestPermission !== 'function') {
      return 'unavailable';
    }
    return this.env.Notification.permission;
  }

  async enable() {
    // Called only from the enable button's click handler. Never request on page load.
    if (this.state() === 'default') {
      await this.env.Notification.requestPermission();
    }
    if (this.state() === 'granted') await this.prepare();
    return this.state();
  }

  async prepare() {
    if (this.registration) return this.registration;
    if (this.preparing) return this.preparing;
    if (!this.env.navigator?.serviceWorker) return null;
    this.preparing = (async () => {
      try {
        const registration = await this.env.navigator.serviceWorker.register('./sw.js', { scope: './' });
        // ready resolves after activation, required by showNotification on mobile.
        const ready = await Promise.race([
          this.env.navigator.serviceWorker.ready,
          new Promise(resolve => this.env.setTimeout(() => resolve(null), 4000)),
        ]);
        this.registration = ready || (registration.active ? registration : null);
        return this.registration;
      } catch { return null; }
      finally { this.preparing = null; }
    })();
    return this.preparing;
  }

  async send(id, title, body) {
    if (this.sent.has(id)) return 'duplicate';
    this.sent.add(id);
    if (this.state() !== 'granted') return 'page-only';
    const options = { body, tag: `one-more-cup-${id}` };
    try {
      const notification = new this.env.Notification(title, options);
      notification.onclick = () => { this.env.focus?.(); notification.close(); };
      return 'sent';
    } catch {
      // Several mobile browsers require a service worker instead of the constructor.
      const registration = await this.prepare();
      if (registration && this.state() === 'granted') {
        try {
          await registration.showNotification(title, options);
          return 'sent';
        } catch { /* The completion card remains visible in the page. */ }
      }
      return 'failed';
    }
  }
}
