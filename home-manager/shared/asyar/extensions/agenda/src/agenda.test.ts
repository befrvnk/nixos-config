function assert(condition: unknown, message?: string): asserts condition {
  if (!condition) {
    throw new Error(message || 'Assertion failed');
  }
}
assert.equal = (a: unknown, b: unknown, msg?: string) => {
  if (a !== b) throw new Error(msg || `Expected ${String(a)} === ${String(b)}`);
};
assert.deepEqual = (a: unknown, b: unknown, msg?: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(msg || `Expected ${JSON.stringify(a)} === ${JSON.stringify(b)}`);
  }
};
assert.ok = (a: unknown, msg?: string) => {
  if (!a) throw new Error(msg || 'Expected truthy value');
};

import { parseIcs, parseIcsDate, unescapeIcs } from './parser';
import { parseRRule, expandEventInstances, deduplicateEvents } from './recurrence';
import { findMeetingLink, getMeetingPlatform, formatTime } from './ui';

function testParser() {
  // Test unescape
  assert.equal(unescapeIcs('Line 1\\nLine 2\\, with comma\\; and semi'), 'Line 1\nLine 2, with comma; and semi');

  // Test date parsing
  const d1 = parseIcsDate('20260918');
  assert.equal(d1?.getFullYear(), 2026);
  assert.equal(d1?.getMonth(), 8); // Sep is 8
  assert.equal(d1?.getDate(), 18);

  const d2 = parseIcsDate('20260918T103000Z');
  assert.equal(d2?.toISOString(), '2026-09-18T10:30:00.000Z');
}

function testRecurrence() {
  const rrule = parseRRule('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;UNTIL=20261231T235959Z');
  assert.equal(rrule.freq, 'WEEKLY');
  assert.equal(rrule.interval, 2);
  assert.deepEqual(rrule.byDay, ['MO', 'WE', 'FR']);
  assert.ok(rrule.until instanceof Date);

  // Bi-weekly meeting test:
  // Starts on Monday Sep 14 2026.
  // Next occurrence should be Monday Sep 28 2026, NOT Monday Sep 21 2026.
  const baseStart = new Date(2026, 8, 14, 10, 0, 0); // Mon Sep 14 2026
  const baseEnd = new Date(2026, 8, 14, 11, 0, 0);

  const evt = {
    summary: 'Bi-weekly Sync',
    start: baseStart,
    end: baseEnd,
    rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO',
  };

  const windowStart = new Date(2026, 8, 14);
  const windowEnd = new Date(2026, 8, 30);
  const instances = expandEventInstances(evt, windowStart, windowEnd);

  assert.equal(instances.length, 2, 'Should have 2 instances: Sep 14 and Sep 28');
  assert.equal(instances[0].start.getDate(), 14);
  assert.equal(instances[1].start.getDate(), 28);
}

function testCancelledAndDeclinedEvents() {
  const now = new Date();
  const dStr = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
  const ics = `BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Active Meeting
UID:active-1@google.com
DTSTART:${dStr}T090000Z
DTEND:${dStr}T100000Z
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=ACCEPTED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
BEGIN:VEVENT
SUMMARY:Cancelled Meeting
UID:cancelled-1@google.com
DTSTART:${dStr}T110000Z
DTEND:${dStr}T120000Z
STATUS:CANCELLED
ATTENDEE;PARTSTAT=ACCEPTED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
BEGIN:VEVENT
SUMMARY:Declined Meeting
UID:declined-1@google.com
DTSTART:${dStr}T130000Z
DTEND:${dStr}T140000Z
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=DECLINED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
END:VCALENDAR`;

  const feedUrl = 'https://calendar.google.com/calendar/ical/frank.hermann%40egym.com/basic.ics';
  const events = parseIcs(ics, feedUrl);

  assert.equal(events.length, 1, 'Only active meeting should be returned');
  assert.equal(events[0].summary, 'Active Meeting');
}

function testExdateSupport() {
  const ics = `BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Repeating Team Sync
UID:repeat-sync@google.com
DTSTART:20260903T090000Z
DTEND:20260903T100000Z
RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=TH
EXDATE:20260910T090000Z,20260924T090000Z
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=ACCEPTED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
END:VCALENDAR`;

  const feedUrl = 'https://calendar.google.com/calendar/ical/frank.hermann%40egym.com/basic.ics';
  const events = parseIcs(ics, feedUrl);

  // Over a 14-day window from Sep 24, Sep 24 should be excluded by EXDATE!
  const sep24 = events.find(e => e.start.getUTCDate() === 24 && e.start.getUTCMonth() === 8);
  assert.equal(sep24, undefined, 'Instance on Sep 24 should be excluded by EXDATE');
}

function testRecurrenceIdOverride() {
  const ics = `BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Series Meeting
UID:series-1@google.com
DTSTART:20260929T170000Z
DTEND:20260929T180000Z
RRULE:FREQ=WEEKLY;INTERVAL=4;BYDAY=TU
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=ACCEPTED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
BEGIN:VEVENT
SUMMARY:Series Meeting (Moved)
UID:series-1@google.com
RECURRENCE-ID:20260929T170000Z
DTSTART:20261006T170000Z
DTEND:20261006T180000Z
STATUS:CONFIRMED
ATTENDEE;PARTSTAT=ACCEPTED;CN=frank.hermann@egym.com:mailto:frank.hermann@egym.com
END:VEVENT
END:VCALENDAR`;

  const feedUrl = 'https://calendar.google.com/calendar/ical/frank.hermann%40egym.com/basic.ics';
  const events = parseIcs(ics, feedUrl);

  const sep29 = events.find(e => e.start.getUTCDate() === 29 && e.start.getUTCMonth() === 8);
  const oct06 = events.find(e => e.start.getUTCDate() === 6 && e.start.getUTCMonth() === 9);

  assert.equal(sep29, undefined, 'Sep 29 should be replaced by the moved instance');
  assert.ok(oct06, 'Oct 6 instance should exist');
}

function testMeetingLinks() {
  const meetEvt = {
    summary: 'Team Standup',
    start: new Date(),
    end: new Date(),
    isAllDay: false,
    location: 'https://meet.google.com/abc-defg-hij',
  };
  const link = findMeetingLink(meetEvt);
  assert.equal(link, 'https://meet.google.com/abc-defg-hij');
  assert.equal(getMeetingPlatform(link), 'Google Meet');

  const zoomEvt = {
    summary: 'Design Review',
    start: new Date(),
    end: new Date(),
    isAllDay: false,
    description: 'Join with Zoom: https://zoom.us/j/1234567890?pwd=secret',
  };
  const zoomLink = findMeetingLink(zoomEvt);
  assert.equal(zoomLink, 'https://zoom.us/j/1234567890?pwd=secret');
  assert.equal(getMeetingPlatform(zoomLink), 'Zoom');
}

function runAll() {
  console.log('Running Agenda TypeScript test suite...');
  testParser();
  console.log('✔ Parser tests passed');
  testRecurrence();
  console.log('✔ Recurrence tests passed');
  testCancelledAndDeclinedEvents();
  console.log('✔ Declined & cancelled filter tests passed');
  testExdateSupport();
  console.log('✔ EXDATE exception dates tests passed');
  testRecurrenceIdOverride();
  console.log('✔ RECURRENCE-ID rescheduled instance tests passed');
  testMeetingLinks();
  console.log('✔ Meeting link detection tests passed');
  console.log('All tests passed successfully! 🎉');
}

runAll();
