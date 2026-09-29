import { CalendarEvent } from './types';
import { parseIcs } from './parser';
import { deduplicateEvents } from './recurrence';
import { renderEvents, updateCardSelection, escapeHtml } from './ui';

const DEFAULT_CALENDAR_URL =
  'https://calendar.google.com/calendar/ical/frank.hermann%40egym.com/private-b5a1340ce7544d21c0039018bb4012d9/basic.ics';

// Safe opener IPC to launch URLs in the default system browser
function openExternalUrl(url: string): void {
  if (!url) return;

  try {
    window.parent.postMessage(
      {
        type: 'asyar:api:opener:open',
        payload: { path: url },
      },
      '*'
    );
  } catch (e) {
    console.error('Failed to post opener:open:', e);
  }

  try {
    window.open(url, '_blank');
  } catch {
    // Ignore fallback errors
  }

  // Dismiss launcher so user focuses their browser
  setTimeout(() => {
    window.parent.postMessage({ type: 'asyar:window:hide' }, '*');
  }, 150);
}

// State
let allEvents: CalendarEvent[] = [];
let filterText = '';
let selectedIndex = 0;
let currentCardCount = 0;
let refreshInProgress = false;
let refreshRequested = false;
let refreshRequestedForce = false;
let feedConfigVersion = 0;
let retryTimer: number | undefined;

const FEED_CACHE_KEY = 'agenda_feed_cache';
const FEED_CACHE_TTL_MS = 60 * 60 * 1000;
const FULL_REFRESH_INTERVAL_MS = 7 * 24 * 60 * 60 * 1000;
const MIN_REQUEST_INTERVAL_MS = 60 * 1000;
const RETRY_BASE_MS = 60 * 1000;
const RETRY_MAX_MS = 6 * 60 * 60 * 1000;

interface FeedCacheEntry {
  fetchedAt: number;
  lastFullFetchAt?: number;
  etag?: string;
  lastModified?: string;
  events: CalendarEvent[];
  failureCount: number;
  retryAfter?: number;
}

interface NetworkResult {
  body: string;
  ok: boolean;
  status: number;
  statusText?: string;
  headers: Record<string, string>;
}

let feedCache = loadFeedCache();

function loadFeedCache(): Record<string, FeedCacheEntry> {
  try {
    const parsed = JSON.parse(localStorage.getItem(FEED_CACHE_KEY) || '{}');
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};

    const cache: Record<string, FeedCacheEntry> = {};
    for (const [url, value] of Object.entries(parsed)) {
      if (!value || typeof value !== 'object') continue;
      const entry = value as Partial<FeedCacheEntry>;
      const events = Array.isArray(entry.events)
        ? entry.events
            .map((event) => {
              const start = new Date(event.start);
              const end = new Date(event.end);
              if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
              return { ...event, start, end };
            })
            .filter((event): event is CalendarEvent => event !== null)
        : [];

      cache[url] = {
        fetchedAt: typeof entry.fetchedAt === 'number' ? entry.fetchedAt : 0,
        lastFullFetchAt: typeof entry.lastFullFetchAt === 'number' ? entry.lastFullFetchAt : undefined,
        etag: entry.etag,
        lastModified: entry.lastModified,
        events,
        failureCount: typeof entry.failureCount === 'number' ? entry.failureCount : 0,
        retryAfter: typeof entry.retryAfter === 'number' ? entry.retryAfter : undefined,
      };
    }
    return cache;
  } catch {
    return {};
  }
}

function saveFeedCache(): void {
  try {
    localStorage.setItem(FEED_CACHE_KEY, JSON.stringify(feedCache));
  } catch {
    // Keep event data and freshness metadata if storage limits are reached.
    const withoutValidators = Object.fromEntries(
      Object.entries(feedCache).map(([url, entry]) => [url, {
        ...entry,
        etag: undefined,
        lastModified: undefined,
      }])
    );
    try {
      localStorage.setItem(FEED_CACHE_KEY, JSON.stringify(withoutValidators));
    } catch {
      // The in-memory cache still works for this session.
    }
  }
}

function responseHeader(headers: Record<string, string>, name: string): string | undefined {
  const key = Object.keys(headers).find((header) => header.toLowerCase() === name.toLowerCase());
  return key ? headers[key] : undefined;
}

function parseRetryAfter(value?: string): number | undefined {
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Date.now() + Math.max(0, seconds) * 1000;
  const date = Date.parse(value);
  return Number.isNaN(date) ? undefined : Math.max(Date.now(), date);
}

function nextRetryTime(failureCount: number, retryAfter?: string): number {
  const exponent = Math.min(Math.max(failureCount - 1, 0), 10);
  const backoff = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * 2 ** exponent);
  const jitteredBackoff = Math.min(RETRY_MAX_MS, backoff * (0.8 + Math.random() * 0.4));
  return Math.max(Date.now() + jitteredBackoff, parseRetryAfter(retryAfter) || 0);
}

function deserializeCachedEvents(value: unknown): CalendarEvent[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((event) => {
      const start = new Date(event?.start);
      const end = new Date(event?.end);
      if (isNaN(start.getTime()) || isNaN(end.getTime())) return null;
      return { ...event, start, end } as CalendarEvent;
    })
    .filter((event): event is CalendarEvent => event !== null);
}

function currentFeedEvents(urls: string[]): CalendarEvent[] {
  return urls.flatMap((url) => feedCache[url]?.events || []);
}

function scheduleRetry(urls: string[] = getUrls()): void {
  if (retryTimer !== undefined) {
    window.clearTimeout(retryTimer);
    retryTimer = undefined;
  }

  const now = Date.now();
  const retryAt = urls
    .map((url) => feedCache[url]?.retryAfter || 0)
    .filter((time) => time > now)
    .sort((a, b) => a - b)[0];
  if (!retryAt) return;

  retryTimer = window.setTimeout(() => {
    retryTimer = undefined;
    if (document.visibilityState === 'visible') {
      void refreshCalendars();
    }
  }, Math.max(0, retryAt - now) + 100);
}

const dateHeading = document.getElementById('date-heading') as HTMLElement;
const syncStatus = document.getElementById('sync-status') as HTMLElement;
const eventsContainer = document.getElementById('events-container') as HTMLElement;
const configPanel = document.getElementById('config-panel') as HTMLElement;
const inputUrls = document.getElementById('input-urls') as HTMLTextAreaElement;
const btnConfig = document.getElementById('btn-config') as HTMLButtonElement;
const btnRefresh = document.getElementById('btn-refresh') as HTMLButtonElement;
const btnSaveConfig = document.getElementById('btn-save-config') as HTMLButtonElement;
const btnCancelConfig = document.getElementById('btn-cancel-config') as HTMLButtonElement;

// Format today header
const now = new Date();
const headerOptions: Intl.DateTimeFormatOptions = { weekday: 'long', month: 'short', day: 'numeric' };
if (dateHeading) {
  dateHeading.textContent = `📅 ${now.toLocaleDateString(undefined, headerOptions)}`;
}

function getUrls(): string[] {
  const raw = localStorage.getItem('agenda_calendar_urls');
  if (raw === null || raw.trim() === '') {
    localStorage.setItem('agenda_calendar_urls', DEFAULT_CALENDAR_URL);
    return [DEFAULT_CALENDAR_URL];
  }
  return raw.split(/[\n,]+/).map(u => u.trim()).filter(Boolean);
}

function saveUrls(urls: string[]): void {
  localStorage.setItem('agenda_calendar_urls', urls.join('\n'));
}

btnConfig?.addEventListener('click', () => {
  if (inputUrls) {
    inputUrls.value = getUrls().join('\n');
  }
  configPanel?.classList.toggle('open');
});

btnCancelConfig?.addEventListener('click', () => {
  configPanel?.classList.remove('open');
});

btnSaveConfig?.addEventListener('click', () => {
  if (!inputUrls) return;
  const urls = inputUrls.value.split(/[\n,]+/).map(u => u.trim()).filter(Boolean);
  saveUrls(urls);
  feedConfigVersion++;
  feedCache = Object.fromEntries(urls.flatMap((url) => feedCache[url] ? [[url, feedCache[url]]] : []));
  saveFeedCache();
  allEvents = deduplicateEvents(currentFeedEvents(urls));
  localStorage.removeItem('agenda_cached_events');
  configPanel?.classList.remove('open');
  render();
  scheduleRetry(urls);
  refreshCalendars(true);
});

btnRefresh?.addEventListener('click', () => {
  refreshCalendars(true);
});

function render(): void {
  currentCardCount = renderEvents({
    events: allEvents,
    filterText,
    container: eventsContainer,
    onOpenUrl: openExternalUrl,
    onSelectIndex: (idx) => {
      selectedIndex = idx;
      updateCardSelection(eventsContainer, selectedIndex);
    },
  });

  if (selectedIndex >= currentCardCount) {
    selectedIndex = Math.max(0, currentCardCount - 1);
  }
  updateCardSelection(eventsContainer, selectedIndex);
}

function handleKeyAction(key: string, metaKey = false, ctrlKey = false): void {
  if ((metaKey || ctrlKey) && (key === 'r' || key === 'R')) {
    refreshCalendars(true);
    return;
  }

  if (key === 'ArrowDown') {
    if (currentCardCount > 0) {
      selectedIndex = (selectedIndex + 1) % currentCardCount;
      updateCardSelection(eventsContainer, selectedIndex);
    }
  } else if (key === 'ArrowUp') {
    if (currentCardCount > 0) {
      selectedIndex = (selectedIndex - 1 + currentCardCount) % currentCardCount;
      updateCardSelection(eventsContainer, selectedIndex);
    }
  } else if (key === 'Enter') {
    const cards = eventsContainer?.querySelectorAll<HTMLElement>('.event-card');
    if (cards && cards.length > 0 && cards[selectedIndex]) {
      const targetUrl = cards[selectedIndex].getAttribute('data-target');
      if (targetUrl) {
        openExternalUrl(targetUrl);
      }
    }
  }
}

// Handle messages forwarded by Asyar host
window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data) return;

  // Host forwarded keydown
  if (data.type === 'asyar:view:keydown' && data.payload) {
    const { key, metaKey, ctrlKey } = data.payload;
    handleKeyAction(key, metaKey, ctrlKey);
  }

  // Host forwarded live search query
  if (data.type === 'asyar:view:search' && data.payload) {
    filterText = (data.payload.query || '').toLowerCase().trim();
    selectedIndex = 0;
    render();
  }

  // Host forwarded Enter submit
  if (data.type === 'asyar:view:submit') {
    const cards = eventsContainer?.querySelectorAll<HTMLElement>('.event-card');
    if (cards && cards.length > 0 && cards[selectedIndex]) {
      const targetUrl = cards[selectedIndex].getAttribute('data-target');
      if (targetUrl) {
        openExternalUrl(targetUrl);
      }
    }
  }

  // Adopt host theme CSS variables
  if (data.type === 'asyar:theme:variables' && data.payload) {
    for (const [k, v] of Object.entries(data.payload)) {
      document.documentElement.style.setProperty(k, String(v));
    }
  }
});

// Direct keydown listener if iframe receives focus
window.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
    e.preventDefault();
  }
  handleKeyAction(e.key, e.metaKey, e.ctrlKey);
});

// IPC-based fetch using Rust reqwest backend (bypasses CORS and CSP)
function asyarFetch(url: string, headers: Record<string, string>): Promise<NetworkResult> {
  return new Promise((resolve, reject) => {
    let fetchUrl = url.trim();
    if (fetchUrl.startsWith('webcal://')) {
      fetchUrl = 'https://' + fetchUrl.substring(9);
    }

    const messageId = crypto.randomUUID();

    const onMessage = (event: MessageEvent) => {
      const data = event.data;
      if (data?.type === 'asyar:response' && data?.messageId === messageId) {
        window.removeEventListener('message', onMessage);
        if (data.error) {
          reject(new Error(data.error));
        } else if (data.result && typeof data.result === 'object') {
          resolve({
            body: typeof data.result.body === 'string' ? data.result.body : '',
            ok: data.result.ok !== false,
            status: typeof data.result.status === 'number' ? data.result.status : 200,
            statusText: typeof data.result.statusText === 'string' ? data.result.statusText : undefined,
            headers: data.result.headers && typeof data.result.headers === 'object'
              ? data.result.headers
              : {},
          });
        } else if (typeof data.result === 'string') {
          resolve({ body: data.result, ok: true, status: 200, headers: {} });
        } else {
          reject(new Error('Empty response from network service'));
        }
      }
    };

    window.addEventListener('message', onMessage);

    try {
      window.parent.postMessage(
        {
          type: 'asyar:api:network:fetch',
          payload: { url: fetchUrl, options: { timeout: 15000, headers } },
          messageId,
        },
        '*'
      );
    } catch (err) {
      window.removeEventListener('message', onMessage);
      reject(err);
    }

    // Fallback timeout after 16s
    setTimeout(() => {
      window.removeEventListener('message', onMessage);
      reject(new Error('Calendar fetch timed out after 16s'));
    }, 16000);
  });
}

async function refreshCalendars(force = false): Promise<void> {
  if (refreshInProgress) {
    refreshRequested = true;
    refreshRequestedForce ||= force;
    return;
  }
  refreshInProgress = true;

  try {
    const urls = getUrls();
    const requestConfigVersion = feedConfigVersion;
    if (urls.length === 0) {
      configPanel?.classList.add('open');
      if (eventsContainer) {
        eventsContainer.innerHTML = `
          <div class="empty-state">
            <p>No calendar feeds configured yet.</p>
            <p style="font-size: 11px;">Paste your Google Calendar, iCloud, or Outlook iCal URL above and click <b>Save Feeds</b>.</p>
          </div>
        `;
      }
      return;
    }

    const now = Date.now();
    const dueUrls = urls.filter((url) => {
      const cached = feedCache[url];
      if (cached?.retryAfter && cached.retryAfter > now) return false;
      if (cached?.fetchedAt && now - cached.fetchedAt < MIN_REQUEST_INTERVAL_MS) return false;
      return force || !cached?.fetchedAt || now - cached.fetchedAt >= FEED_CACHE_TTL_MS;
    });

    if (dueUrls.length === 0) {
      const retryAt = urls
        .map((url) => feedCache[url]?.retryAfter || 0)
        .filter((time) => time > now)
        .sort((a, b) => a - b)[0];
      scheduleRetry(urls);
      if (syncStatus) {
        syncStatus.textContent = retryAt
          ? `Retry paused · retry in ${Math.ceil((retryAt - now) / 60000)}m`
          : `Cached (${currentFeedEvents(urls).length} events)`;
      }
      return;
    }

    if (syncStatus) syncStatus.textContent = 'Syncing...';
    const errors = urls
      .filter((url) => feedCache[url]?.retryAfter && feedCache[url].retryAfter! > now)
      .map(() => 'Calendar feed is waiting for its retry backoff');
    let fetchedCount = 0;

    // Fetch sequentially to avoid sending a burst when several feeds are configured.
    for (const url of dueUrls) {
      const cached = feedCache[url] || {
        fetchedAt: 0,
        events: [],
        failureCount: 0,
      };
      const headers: Record<string, string> = {};
      // parseIcs expands 14 days of recurrences, so force a full fetch weekly
      // to rebuild that rolling window before its cached occurrences run out.
      const canUseValidators = cached.lastFullFetchAt &&
        Date.now() - cached.lastFullFetchAt < FULL_REFRESH_INTERVAL_MS;
      if (canUseValidators && cached.etag) headers['If-None-Match'] = cached.etag;
      if (canUseValidators && cached.lastModified) headers['If-Modified-Since'] = cached.lastModified;

      try {
        const response = await asyarFetch(url, headers);
        if (requestConfigVersion !== feedConfigVersion || !getUrls().includes(url)) break;
        if (response.status === 304) {
          if (!cached.fetchedAt) {
            cached.etag = undefined;
            cached.lastModified = undefined;
            throw new Error('Calendar returned 304 without cached events; retrying without validators');
          }
          cached.fetchedAt = Date.now();
          cached.failureCount = 0;
          cached.retryAfter = undefined;
          cached.etag = responseHeader(response.headers, 'etag') || cached.etag;
          cached.lastModified = responseHeader(response.headers, 'last-modified') || cached.lastModified;
          feedCache[url] = cached;
          fetchedCount++;
          continue;
        }

        if (!response.ok) {
          const status = response.status ? `HTTP ${response.status}` : 'HTTP error';
          const statusText = response.statusText ? ` ${response.statusText}` : '';
          const error = new Error(`Calendar feed request failed (${status}${statusText})`);
          cached.failureCount++;
          cached.retryAfter = nextRetryTime(
            cached.failureCount,
            responseHeader(response.headers, 'retry-after')
          );
          feedCache[url] = cached;
          errors.push(error.message);
          console.warn('Failed calendar feed:', error);
          continue;
        }

        if (!response.body) throw new Error('Empty response from network service');

        cached.events = parseIcs(response.body, url);
        cached.fetchedAt = Date.now();
        cached.lastFullFetchAt = cached.fetchedAt;
        cached.etag = responseHeader(response.headers, 'etag');
        cached.lastModified = responseHeader(response.headers, 'last-modified');
        cached.failureCount = 0;
        cached.retryAfter = undefined;
        feedCache[url] = cached;
        fetchedCount++;
      } catch (err: unknown) {
        if (requestConfigVersion !== feedConfigVersion || !getUrls().includes(url)) break;
        const message = err instanceof Error ? err.message : String(err);
        cached.failureCount++;
        cached.retryAfter = nextRetryTime(cached.failureCount);
        feedCache[url] = cached;
        errors.push(message);
        console.warn('Failed calendar feed:', err);
      }

      saveFeedCache();
    }

    if (requestConfigVersion !== feedConfigVersion) return;
    saveFeedCache();
    scheduleRetry(urls);
    const cachedEvents = currentFeedEvents(urls);
    if (cachedEvents.length > 0 || urls.every((url) => feedCache[url])) {
      allEvents = deduplicateEvents(cachedEvents.filter((event) => event.start != null));
      localStorage.removeItem('agenda_cached_events');
    }

    if (errors.length > 0) {
      const message = errors[0];
      if (syncStatus) {
        syncStatus.textContent = fetchedCount > 0
          ? `Updated · ${errors.length} feed${errors.length === 1 ? '' : 's'} unavailable`
          : 'Sync error';
      }
      if (allEvents.length === 0 && eventsContainer) {
        eventsContainer.innerHTML = `
          <div class="empty-state">
            <p>Could not load calendar feed: ${escapeHtml(message)}</p>
            <p style="font-size: 11px;">The feed will be retried automatically after a backoff. Click ⚙️ Feeds to verify its URL.</p>
          </div>
        `;
      } else {
        render();
      }
      return;
    }

    if (syncStatus) syncStatus.textContent = `Updated (${allEvents.length} events)`;
    render();
  } finally {
    refreshInProgress = false;
    if (refreshRequested) {
      const forceRequested = refreshRequestedForce;
      refreshRequested = false;
      refreshRequestedForce = false;
      void refreshCalendars(forceRequested);
    }
  }
}

// Restore per-feed cache first, then fall back to the previous aggregate cache format.
const configuredUrls = getUrls();
const hasFeedCache = configuredUrls.some((url) => feedCache[url]);
if (hasFeedCache) {
  allEvents = deduplicateEvents(currentFeedEvents(configuredUrls));
  localStorage.removeItem('agenda_cached_events');
  render();
} else {
  try {
    allEvents = deserializeCachedEvents(JSON.parse(localStorage.getItem('agenda_cached_events') || '[]'));
  } catch {
    allEvents = [];
  }
  if (allEvents.length > 0) render();
}

// Refresh only when cached data is stale; skip background polling while hidden.
void refreshCalendars();
setInterval(() => {
  if (document.visibilityState === 'visible') void refreshCalendars();
}, FEED_CACHE_TTL_MS);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') void refreshCalendars();
});
