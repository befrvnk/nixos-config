import { CalendarEvent, RawCalendarEvent } from './types';
import { expandEventInstances, deduplicateEvents } from './recurrence';

export function unescapeIcs(str: string): string {
  return str
    .replace(/\\n/gi, '\n')
    .replace(/\\,/g, ',')
    .replace(/\\;/g, ';')
    .replace(/\\\\/g, '\\');
}

export function parseIcsDate(str?: string | null): Date | null {
  if (!str) return null;
  const s = str.trim();

  if (s.length === 8 && /^\d{8}$/.test(s)) {
    const y = parseInt(s.substring(0, 4), 10);
    const m = parseInt(s.substring(4, 6), 10) - 1;
    const d = parseInt(s.substring(6, 8), 10);
    return new Date(y, m, d, 0, 0, 0);
  }

  const match = s.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/);
  if (match) {
    const [, y, mo, d, h, mi, sec, isUtc] = match;
    if (isUtc) {
      return new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +sec));
    }
    return new Date(+y, +mo - 1, +d, +h, +mi, +sec);
  }

  const fallback = new Date(s);
  return isNaN(fallback.getTime()) ? null : fallback;
}

export function parseIcs(icsText: string, feedUrl?: string): CalendarEvent[] {
  let feedUser = '';
  if (feedUrl) {
    const match = feedUrl.match(/\/ical\/([^/]+)\//);
    if (match) {
      try {
        feedUser = decodeURIComponent(match[1]).toLowerCase();
      } catch {
        // Ignore URI decode errors
      }
    }
  }

  const rawEvents: RawCalendarEvent[] = [];
  const unfolded = icsText.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '');
  const lines = unfolded.split(/\r?\n/);

  let inEvent = false;
  let current: RawCalendarEvent = {};

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    if (line === 'BEGIN:VEVENT') {
      inEvent = true;
      current = { isDeclined: false, isCancelled: false, exdates: [] };
      continue;
    }

    if (line === 'END:VEVENT') {
      if (inEvent && current.summary && current.start) {
        if (!current.isDeclined && !current.isCancelled) {
          rawEvents.push(current);
        }
      }
      inEvent = false;
      continue;
    }

    if (!inEvent) continue;

    const colonIdx = line.indexOf(':');
    if (colonIdx === -1) continue;

    const propPart = line.substring(0, colonIdx);
    const val = line.substring(colonIdx + 1);
    const propName = propPart.split(';')[0].toUpperCase();

    if (propName === 'SUMMARY') {
      current.summary = unescapeIcs(val);
    } else if (propName === 'UID') {
      current.uid = val.trim();
    } else if (propName === 'RECURRENCE-ID') {
      current.recurrenceId = parseIcsDate(val) ?? undefined;
    } else if (propName === 'EXDATE') {
      for (const dStr of val.split(',')) {
        const d = parseIcsDate(dStr.trim());
        if (d) {
          current.exdates = current.exdates || [];
          current.exdates.push(d);
        }
      }
    } else if (propName === 'DTSTART') {
      current.start = parseIcsDate(val) ?? undefined;
      current.isAllDay = val.length === 8;
    } else if (propName === 'DTEND') {
      current.end = parseIcsDate(val) ?? undefined;
    } else if (propName === 'RRULE') {
      current.rrule = val;
    } else if (propName === 'STATUS') {
      if (val.trim().toUpperCase() === 'CANCELLED') {
        current.isCancelled = true;
      }
    } else if (propName === 'ATTENDEE') {
      const upperProp = propPart.toUpperCase();
      if (upperProp.includes('PARTSTAT=DECLINED')) {
        const lowerLine = line.toLowerCase();
        if (feedUser && lowerLine.includes(feedUser)) {
          current.isDeclined = true;
        } else if (!feedUser) {
          current.isDeclined = true;
        }
      }
    } else if (propName === 'LOCATION') {
      current.location = unescapeIcs(val);
    } else if (propName === 'DESCRIPTION') {
      current.description = unescapeIcs(val);
    } else if (propName === 'URL') {
      current.url = val;
    }
  }

  // Expand recurrence rules over target time window (today to +14 days)
  const now = new Date();
  const windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const windowEnd = new Date(windowStart.getTime() + 14 * 24 * 60 * 60 * 1000);

  const expandedEvents: CalendarEvent[] = [];
  for (const evt of rawEvents) {
    const instances = expandEventInstances(evt, windowStart, windowEnd);
    expandedEvents.push(...instances);
  }

  return deduplicateEvents(expandedEvents);
}
