import { CalendarEvent } from './types';

export function decodeCalendarEvents(stdout: string): CalendarEvent[] {
  let result;
  try { result = JSON.parse(stdout); } catch {
    throw new Error('ical-guy returned no valid event JSON. Check calendar access in System Settings → Privacy & Security → Calendars, then refresh Agenda.');
  }
  if (!Array.isArray(result)) throw new Error('Invalid response from ical-guy');
  return result.flatMap((event) => {
    if (!event || typeof event !== 'object') throw new Error('Invalid calendar event');
    const start = new Date(event.startDate);
    const end = new Date(event.endDate);
    if (typeof event.title !== 'string' || typeof event.startDate !== 'string' ||
        typeof event.endDate !== 'string' || typeof event.isAllDay !== 'boolean' ||
        isNaN(start.getTime()) || isNaN(end.getTime())) {
      throw new Error('Invalid calendar event');
    }
    if (event.status === 'canceled' || event.status === 'cancelled' ||
        (Array.isArray(event.attendees) && event.attendees.some(
          (attendee: { isCurrentUser?: boolean; status?: string }) =>
            attendee?.isCurrentUser === true && attendee.status === 'declined'
        ))) return [];
    return [{
      summary: event.title, start, end, isAllDay: event.isAllDay,
      location: typeof event.location === 'string' ? event.location : undefined,
      description: typeof event.notes === 'string' ? event.notes : undefined,
      url: typeof event.meetingUrl === 'string' && event.meetingUrl
        ? event.meetingUrl : typeof event.url === 'string' ? event.url : undefined,
    }];
  });
}

export function fetchEventKitEvents(): Promise<CalendarEvent[]> {
  return new Promise((resolve, reject) => {
    const spawnId = crypto.randomUUID();
    const messageId = crypto.randomUUID();
    let stdout = '';
    const cleanup = () => {
      window.removeEventListener('message', onMessage);
      window.clearTimeout(timer);
    };
    const onMessage = (event: MessageEvent) => {
      const msg = event.data;
      if (msg?.type === 'asyar:response' && msg.messageId === messageId && msg.error) {
        cleanup();
        reject(new Error(msg.error));
      }
      if (msg?.type !== 'asyar:stream' || msg.streamId !== spawnId) return;
      if (msg.phase === 'chunk' && msg.data?.text) stdout += msg.data.text;
      if (msg.phase === 'done' || msg.phase === 'error') {
        cleanup();
        try {
          if (msg.phase === 'error') {
            throw new Error(msg.data?.error?.message || stdout || 'ical-guy failed. Check calendar access in System Settings → Privacy & Security → Calendars.');
          }
          resolve(decodeCalendarEvents(stdout));
        } catch (error) { reject(error); }
      }
    };
    const timer = window.setTimeout(() => {
      cleanup();
      reject(new Error('ical-guy timed out. Approve calendar access in System Settings → Privacy & Security → Calendars, then refresh Agenda.'));
    }, 60000);
    window.addEventListener('message', onMessage);
    try {
      window.parent.postMessage({
        type: 'asyar:api:shell:spawn',
        payload: {
          program: '@calendarProgram@',
          args: ['events', '--from', 'today', '--to', 'today+14', '--group-by', 'none', '--format', 'json'],
          spawnId,
        },
        messageId,
      }, '*');
    } catch (error) { cleanup(); reject(error); }
  });
}
