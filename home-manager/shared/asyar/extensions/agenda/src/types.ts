export interface CalendarEvent {
  summary: string;
  start: Date;
  end: Date;
  isAllDay: boolean;
  location?: string;
  description?: string;
  url?: string;
}

export interface RawCalendarEvent {
  summary?: string;
  start?: Date;
  end?: Date;
  isAllDay?: boolean;
  isDeclined?: boolean;
  isCancelled?: boolean;
  location?: string;
  description?: string;
  url?: string;
  rrule?: string;
}

export interface ParsedRRule {
  freq?: string;
  interval: number;
  until?: Date;
  count?: number;
  byDay: string[];
}
