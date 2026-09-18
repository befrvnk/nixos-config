import { CalendarEvent } from './types';

export function escapeHtml(str: string): string {
  const p = document.createElement('p');
  p.textContent = str;
  return p.innerHTML;
}

const MEETING_REGEX = /https?:\/\/(?:[a-zA-Z0-9-]+\.)?(?:zoom\.us\/j\/\S+|meet\.google\.com\/\S+|teams\.microsoft\.com\/l\/meetup-join\/\S+|webex\.com\/\S+|meet\.jit\.si\/\S+)/i;

export function findMeetingLink(evt: CalendarEvent): string | null {
  if (evt.url && MEETING_REGEX.test(evt.url)) return evt.url;
  if (evt.location && MEETING_REGEX.test(evt.location)) {
    const m = evt.location.match(MEETING_REGEX);
    if (m) return m[0];
  }
  if (evt.description && MEETING_REGEX.test(evt.description)) {
    const m = evt.description.match(MEETING_REGEX);
    if (m) return m[0];
  }
  return null;
}

export function getMeetingPlatform(url: string | null): string {
  if (!url) return 'Meeting';
  if (url.includes('meet.google.com')) return 'Google Meet';
  if (url.includes('zoom.us')) return 'Zoom';
  if (url.includes('teams.microsoft.com')) return 'Teams';
  if (url.includes('webex.com')) return 'Webex';
  if (url.includes('jit.si')) return 'Jitsi';
  return 'Meeting Call';
}

export function formatTime(d?: Date): string {
  if (!d) return '';
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export interface RenderOptions {
  events: CalendarEvent[];
  filterText: string;
  container: HTMLElement;
  onOpenUrl: (url: string) => void;
  onSelectIndex: (idx: number) => void;
}

export function renderEvents(options: RenderOptions): number {
  const { events, filterText, container, onOpenUrl, onSelectIndex } = options;
  const currentTime = new Date();
  const startOfToday = new Date(currentTime.getFullYear(), currentTime.getMonth(), currentTime.getDate());
  const sevenDaysLater = new Date(startOfToday.getTime() + 8 * 24 * 60 * 60 * 1000);

  const filtered = events.filter(e => {
    if (!e.start) return false;
    if (e.end && e.end < startOfToday) return false;
    if (!e.end && e.start < startOfToday) return false;
    if (e.start > sevenDaysLater) return false;

    if (filterText) {
      const q = filterText.toLowerCase();
      const titleMatch = (e.summary || '').toLowerCase().includes(q);
      const locMatch = (e.location || '').toLowerCase().includes(q);
      return titleMatch || locMatch;
    }
    return true;
  });

  filtered.sort((a, b) => a.start.getTime() - b.start.getTime());

  if (filtered.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <p>No upcoming events found for this week.</p>
      </div>
    `;
    return 0;
  }

  // Group events by day
  const byDay = new Map<number, CalendarEvent[]>();
  const happeningNow: CalendarEvent[] = [];

  const todayKey = new Date(currentTime.getFullYear(), currentTime.getMonth(), currentTime.getDate()).getTime();
  const tomorrowKey = todayKey + 24 * 60 * 60 * 1000;

  for (const evt of filtered) {
    const isNow = evt.start <= currentTime && evt.end && evt.end > currentTime;
    if (isNow) {
      happeningNow.push(evt);
    }

    const dayKey = new Date(evt.start.getFullYear(), evt.start.getMonth(), evt.start.getDate()).getTime();
    if (!byDay.has(dayKey)) {
      byDay.set(dayKey, []);
    }
    byDay.get(dayKey)!.push(evt);
  }

  let html = '';

  function renderGroup(title: string, list: CalendarEvent[], isNowGroup = false): string {
    if (list.length === 0) return '';
    let out = `<div class="section-title">${title} (${list.length})</div>`;
    for (const evt of list) {
      const meetingUrl = findMeetingLink(evt);
      const meetingName = getMeetingPlatform(meetingUrl);
      const isNow = isNowGroup || (evt.start <= currentTime && evt.end && evt.end > currentTime);
      const isPast = evt.end && evt.end < currentTime;

      const timeStr = evt.isAllDay ? 'All day' : `${formatTime(evt.start)} - ${formatTime(evt.end)}`;

      let badge = '';
      if (isNow) {
        badge = `<span class="event-badge badge-now">Happening Now</span>`;
      } else if (isPast) {
        badge = `<span class="event-badge" style="opacity: 0.6;">Finished</span>`;
      } else if (evt.start.getTime() > currentTime.getTime() && (evt.start.getTime() - currentTime.getTime()) < 60 * 60 * 1000) {
        const mins = Math.round((evt.start.getTime() - currentTime.getTime()) / (60 * 1000));
        badge = `<span class="event-badge badge-soon">In ${mins}m</span>`;
      }

      let joinButton = '';
      if (meetingUrl && !isPast) {
        joinButton = `<button class="join-btn" data-url="${escapeHtml(meetingUrl)}">Join ${meetingName}</button>`;
      }

      out += `
        <div class="event-card ${isNow ? 'happening-now' : ''}" style="${isPast ? 'opacity: 0.55;' : ''}" data-target="${escapeHtml(meetingUrl || evt.url || '')}">
          <div class="event-main">
            <div class="event-title">${escapeHtml(evt.summary || 'Untitled Event')}</div>
            <div class="event-meta">
              <span>🕒 ${timeStr}</span>
              ${evt.location ? `<span>📍 ${escapeHtml(evt.location)}</span>` : ''}
              ${badge}
            </div>
          </div>
          ${joinButton}
        </div>
      `;
    }
    return out;
  }

  if (happeningNow.length > 0) {
    html += renderGroup('⚡ Happening Now', happeningNow, true);
  }

  const sortedDayKeys = Array.from(byDay.keys()).sort((a, b) => a - b);
  for (const dayKey of sortedDayKeys) {
    const evts = byDay.get(dayKey)!;
    const d = new Date(dayKey);
    let dayTitle = '';
    if (dayKey === todayKey) {
      dayTitle = `Today — ${d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' })}`;
    } else if (dayKey === tomorrowKey) {
      dayTitle = `Tomorrow — ${d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' })}`;
    } else {
      dayTitle = d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' });
    }

    html += renderGroup(dayTitle, evts);
  }

  container.innerHTML = html;

  // Attach card click handlers
  const cards = container.querySelectorAll<HTMLElement>('.event-card');
  cards.forEach((card, idx) => {
    card.addEventListener('click', () => {
      onSelectIndex(idx);
      const target = card.getAttribute('data-target');
      if (target) {
        onOpenUrl(target);
      }
    });
  });

  // Attach Join button click handlers
  container.querySelectorAll<HTMLButtonElement>('.join-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const url = btn.getAttribute('data-url');
      if (url) {
        onOpenUrl(url);
      }
    });
  });

  return cards.length;
}

export function updateCardSelection(container: HTMLElement, selectedIndex: number): void {
  const cards = container.querySelectorAll<HTMLElement>('.event-card');
  cards.forEach((c, i) => {
    if (i === selectedIndex) {
      c.classList.add('selected');
      c.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    } else {
      c.classList.remove('selected');
    }
  });
}
