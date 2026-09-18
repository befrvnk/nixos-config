import { CalendarEvent, RawCalendarEvent, ParsedRRule } from './types';
import { parseIcsDate } from './parser';

export const DAY_MAP: Record<string, number> = {
  SU: 0,
  MO: 1,
  TU: 2,
  WE: 3,
  TH: 4,
  FR: 5,
  SA: 6,
};

export function parseRRule(rruleStr: string): ParsedRRule {
  const ruleParts: Record<string, string> = {};
  for (const part of rruleStr.split(';')) {
    const idx = part.indexOf('=');
    if (idx !== -1) {
      ruleParts[part.substring(0, idx).toUpperCase()] = part.substring(idx + 1);
    }
  }

  const byDayRaw = ruleParts['BYDAY'];
  return {
    freq: ruleParts['FREQ'],
    interval: parseInt(ruleParts['INTERVAL'] || '1', 10),
    until: ruleParts['UNTIL'] ? (parseIcsDate(ruleParts['UNTIL']) ?? undefined) : undefined,
    count: ruleParts['COUNT'] ? parseInt(ruleParts['COUNT'], 10) : undefined,
    byDay: byDayRaw ? byDayRaw.split(',') : [],
  };
}

export function expandEventInstances(
  evt: RawCalendarEvent,
  startPeriod: Date,
  endPeriod: Date
): CalendarEvent[] {
  if (!evt.start || !evt.summary) return [];

  const baseStart = evt.start;
  const baseEnd = evt.end || new Date(baseStart.getTime() + 30 * 60 * 1000);
  const duration = baseEnd.getTime() - baseStart.getTime();

  if (!evt.rrule) {
    if (baseEnd >= startPeriod && baseStart <= endPeriod) {
      return [
        {
          summary: evt.summary,
          start: baseStart,
          end: baseEnd,
          isAllDay: !!evt.isAllDay,
          location: evt.location,
          description: evt.description,
          url: evt.url,
        },
      ];
    }
    return [];
  }

  const rule = parseRRule(evt.rrule);
  const instances: CalendarEvent[] = [];

  const baseMonday = new Date(baseStart.getFullYear(), baseStart.getMonth(), baseStart.getDate());
  const baseDay = (baseMonday.getDay() + 6) % 7; // Monday = 0
  baseMonday.setDate(baseMonday.getDate() - baseDay);

  const cur = new Date(startPeriod.getFullYear(), startPeriod.getMonth(), startPeriod.getDate());
  const endDate = new Date(endPeriod.getFullYear(), endPeriod.getMonth(), endPeriod.getDate());

  let matchCount = 0;
  while (cur <= endDate) {
    if (cur < new Date(baseStart.getFullYear(), baseStart.getMonth(), baseStart.getDate())) {
      cur.setDate(cur.getDate() + 1);
      continue;
    }
    if (rule.until && cur > rule.until) break;

    const curMonday = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate());
    const curDay = (curMonday.getDay() + 6) % 7; // Monday = 0
    curMonday.setDate(curMonday.getDate() - curDay);

    const weeksDiff = Math.round((curMonday.getTime() - baseMonday.getTime()) / (7 * 24 * 60 * 60 * 1000));
    const dayOfWeek = cur.getDay();

    let matches = false;
    if (rule.freq === 'DAILY') {
      const daysDiff = Math.round((cur.getTime() - baseStart.getTime()) / (24 * 60 * 60 * 1000));
      matches = daysDiff % rule.interval === 0;
    } else if (rule.freq === 'WEEKLY') {
      if (weeksDiff % rule.interval === 0) {
        if (rule.byDay.length > 0) {
          matches = rule.byDay.some(code => DAY_MAP[code] === dayOfWeek);
        } else {
          matches = dayOfWeek === baseStart.getDay();
        }
      }
    } else if (rule.freq === 'MONTHLY') {
      const monthsDiff = (cur.getFullYear() - baseStart.getFullYear()) * 12 + (cur.getMonth() - baseStart.getMonth());
      matches = monthsDiff % rule.interval === 0 && cur.getDate() === baseStart.getDate();
    }

    if (matches) {
      matchCount++;
      if (rule.count && matchCount > rule.count) break;

      const instStart = new Date(
        cur.getFullYear(),
        cur.getMonth(),
        cur.getDate(),
        baseStart.getHours(),
        baseStart.getMinutes(),
        baseStart.getSeconds()
      );
      const instEnd = new Date(instStart.getTime() + duration);

      instances.push({
        summary: evt.summary,
        start: instStart,
        end: instEnd,
        isAllDay: !!evt.isAllDay,
        location: evt.location,
        description: evt.description,
        url: evt.url,
      });
    }

    cur.setDate(cur.getDate() + 1);
  }

  return instances;
}

export function deduplicateEvents(events: CalendarEvent[]): CalendarEvent[] {
  const seen = new Set<string>();
  return events.filter(e => {
    const key = `${e.summary}_${e.start.getTime()}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
