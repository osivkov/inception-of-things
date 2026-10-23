// Notification display only. No offline cache, background timer, push subscription or scheduler.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const origin = new URL(self.registration.scope).origin;
    const existing = windows.find(client => new URL(client.url).origin === origin);
    if (existing) return existing.focus();
    return self.clients.openWindow(self.registration.scope);
  })());
});
