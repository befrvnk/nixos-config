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
  configPanel?.classList.remove('open');
  refreshCalendars();
});

btnRefresh?.addEventListener('click', () => {
  refreshCalendars();
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
    refreshCalendars();
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
function asyarFetch(url: string): Promise<string> {
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
        } else if (data.result?.body) {
          resolve(data.result.body);
        } else if (typeof data.result === 'string') {
          resolve(data.result);
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
          payload: { url: fetchUrl, options: { timeout: 15000 } },
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

async function refreshCalendars(): Promise<void> {
  const urls = getUrls();
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

  if (syncStatus) syncStatus.textContent = 'Syncing...';
  try {
    const results = await Promise.allSettled(
      urls.map((url) => asyarFetch(url).then((text) => parseIcs(text, url)))
    );
    const events: CalendarEvent[] = [];
    let successCount = 0;
    for (const r of results) {
      if (r.status === 'fulfilled') {
        events.push(...r.value);
        successCount++;
      } else {
        console.warn('Failed calendar feed:', r.reason);
      }
    }

    if (successCount === 0 && results.length > 0) {
      const firstRejected = results.find((r) => r.status === 'rejected') as PromiseRejectedResult | undefined;
      throw firstRejected?.reason || new Error('Failed to load calendar');
    }

    allEvents = deduplicateEvents(events.filter((e) => e.start != null));
    localStorage.setItem('agenda_cached_events', JSON.stringify(allEvents));
    if (syncStatus) {
      syncStatus.textContent = `Updated (${allEvents.length} events)`;
      setTimeout(() => {
        syncStatus.textContent = '';
      }, 3000);
    }
    render();
  } catch (err: unknown) {
    if (syncStatus) {
      syncStatus.textContent = 'Sync error';
      setTimeout(() => {
        syncStatus.textContent = '';
      }, 4000);
    }
    const message = err instanceof Error ? err.message : String(err);
    console.error('Refresh error:', err);
    if (allEvents.length === 0 && eventsContainer) {
      eventsContainer.innerHTML = `
        <div class="empty-state">
          <p>Could not load calendar feed: ${escapeHtml(message)}</p>
          <p style="font-size: 11px;">Click ⚙️ Feeds to verify your iCal / ICS URL.</p>
        </div>
      `;
    }
  }
}

// Restore cache on launch
const cached = localStorage.getItem('agenda_cached_events');
if (cached) {
  try {
    const parsed = JSON.parse(cached);
    if (Array.isArray(parsed) && parsed.length > 0) {
      allEvents = parsed.map((e: CalendarEvent) => ({
        ...e,
        start: new Date(e.start),
        end: e.end ? new Date(e.end) : new Date(new Date(e.start).getTime() + 30 * 60 * 1000),
      }));
      render();
    }
  } catch {
    // Ignore cache parse error
  }
}

// Initial fetch and auto-refresh every 5 minutes
refreshCalendars();
setInterval(refreshCalendars, 5 * 60 * 1000);
