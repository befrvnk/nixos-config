(function () {
  const EXTENSION_ID = 'org.asyar.agenda';
  const DEFAULT_CALENDAR_URL = 'https://calendar.google.com/calendar/ical/frank.hermann%40egym.com/private-b5a1340ce7544d21c0039018bb4012d9/basic.ics';

  // Inform Asyar host that view is loaded
  try {
    window.parent.postMessage({ type: 'asyar:extension:loaded', extensionId: EXTENSION_ID, role: 'view' }, '*');
  } catch (e) {
    console.error('Failed to notify host:', e);
  }

  // Forward Cmd/Ctrl+K and Escape to host
  window.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      window.parent.postMessage({
        type: 'asyar:extension:keydown',
        payload: { key: e.key, metaKey: e.metaKey, ctrlKey: e.ctrlKey }
      }, '*');
    }
  });

  // Adopt host theme variables
  window.addEventListener('message', (event) => {
    if (event.data?.type === 'asyar:theme:variables' && event.data?.payload) {
      const vars = event.data.payload;
      for (const [k, v] of Object.entries(vars)) {
        document.documentElement.style.setProperty(k, v);
      }
    }
  });

  // State
  let allEvents = [];
  let filterText = '';

  const dateHeading = document.getElementById('date-heading');
  const syncStatus = document.getElementById('sync-status');
  const eventsContainer = document.getElementById('events-container');
  const searchInput = document.getElementById('search-input');
  const configPanel = document.getElementById('config-panel');
  const inputUrls = document.getElementById('input-urls');
  const btnConfig = document.getElementById('btn-config');
  const btnRefresh = document.getElementById('btn-refresh');
  const btnSaveConfig = document.getElementById('btn-save-config');
  const btnCancelConfig = document.getElementById('btn-cancel-config');

  // Format today header
  const now = new Date();
  const options = { weekday: 'long', month: 'short', day: 'numeric' };
  dateHeading.textContent = `📅 ${now.toLocaleDateString(undefined, options)}`;

  // Load configured URLs
  function getUrls() {
    const raw = localStorage.getItem('agenda_calendar_urls');
    if (raw === null || raw.trim() === '') {
      localStorage.setItem('agenda_calendar_urls', DEFAULT_CALENDAR_URL);
      return [DEFAULT_CALENDAR_URL];
    }
    return raw.split(/[\n,]+/).map(u => u.trim()).filter(Boolean);
  }

  function saveUrls(urls) {
    localStorage.setItem('agenda_calendar_urls', urls.join('\n'));
  }

  btnConfig.addEventListener('click', () => {
    inputUrls.value = getUrls().join('\n');
    configPanel.classList.toggle('open');
  });

  btnCancelConfig.addEventListener('click', () => {
    configPanel.classList.remove('open');
  });

  btnSaveConfig.addEventListener('click', () => {
    const lines = inputUrls.value.split(/[\n,]+/).map(s => s.trim()).filter(Boolean);
    saveUrls(lines);
    configPanel.classList.remove('open');
    refreshCalendars();
  });

  btnRefresh.addEventListener('click', () => {
    refreshCalendars();
  });

  searchInput.addEventListener('input', (e) => {
    filterText = e.target.value.toLowerCase().trim();
    render();
  });

  // IPC-based fetch using Rust reqwest backend (bypasses CORS and CSP)
  function asyarFetch(url) {
    return new Promise((resolve, reject) => {
      let fetchUrl = url.trim();
      if (fetchUrl.startsWith('webcal://')) {
        fetchUrl = 'https://' + fetchUrl.substring(9);
      }

      const messageId = crypto.randomUUID();

      const onMessage = (event) => {
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

      // Post IPC invoke to parent host
      try {
        window.parent.postMessage({
          type: 'asyar:api:network:fetch',
          payload: { url: fetchUrl, options: { timeout: 15000 } },
          messageId
        }, '*');
      } catch (err) {
        window.removeEventListener('message', onMessage);
        reject(err);
      }

      // Fallback timeout after 16s
      setTimeout(() => {
        window.removeEventListener('message', onMessage);
        // If IPC timed out, try standard browser fetch as a fallback
        fetch(fetchUrl, { cache: 'no-store' })
          .then(res => res.text())
          .then(resolve)
          .catch(() => reject(new Error('Fetch timed out')));
      }, 16000);
    });
  }

  // Parse iCalendar VEVENT blocks with RRULE recurrence expansion
  const DAY_MAP = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

  function parseIcs(icsText) {
    const rawEvents = [];
    const unfolded = icsText.replace(/\r\n[ \t]/g, '').replace(/\n[ \t]/g, '');
    const lines = unfolded.split(/\r?\n/);

    let inEvent = false;
    let current = {};

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;

      if (line === 'BEGIN:VEVENT') {
        inEvent = true;
        current = {};
        continue;
      }

      if (line === 'END:VEVENT') {
        if (inEvent && current.summary && current.start) {
          rawEvents.push(current);
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
      } else if (propName === 'DTSTART') {
        current.start = parseIcsDate(val);
        current.isAllDay = val.length === 8;
      } else if (propName === 'DTEND') {
        current.end = parseIcsDate(val);
      } else if (propName === 'RRULE') {
        current.rrule = val;
      } else if (propName === 'LOCATION') {
        current.location = unescapeIcs(val);
      } else if (propName === 'DESCRIPTION') {
        current.description = unescapeIcs(val);
      } else if (propName === 'URL') {
        current.url = val;
      }
    }

    // Expand recurrence rules over target time window (today to +14 days)
    const windowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const windowEnd = new Date(windowStart.getTime() + 14 * 24 * 60 * 60 * 1000);

    const expandedEvents = [];
    for (const evt of rawEvents) {
      const instances = expandEventInstances(evt, windowStart, windowEnd);
      expandedEvents.push(...instances);
    }

    return deduplicateEvents(expandedEvents);
  }

  function expandEventInstances(evt, startPeriod, endPeriod) {
    const baseStart = evt.start;
    const baseEnd = evt.end || new Date(baseStart.getTime() + 30 * 60 * 1000);
    const duration = baseEnd.getTime() - baseStart.getTime();

    if (!evt.rrule) {
      if (baseEnd >= startPeriod && baseStart <= endPeriod) {
        return [evt];
      }
      return [];
    }

    const instances = [];
    const ruleParts = {};
    evt.rrule.split(';').forEach(p => {
      const idx = p.indexOf('=');
      if (idx !== -1) {
        ruleParts[p.substring(0, idx).toUpperCase()] = p.substring(idx + 1);
      }
    });

    const freq = ruleParts['FREQ'];
    const byDay = ruleParts['BYDAY'] ? ruleParts['BYDAY'].split(',') : null;
    const until = ruleParts['UNTIL'] ? parseIcsDate(ruleParts['UNTIL']) : null;
    const count = ruleParts['COUNT'] ? parseInt(ruleParts['COUNT'], 10) : null;

    let cur = new Date(startPeriod.getFullYear(), startPeriod.getMonth(), startPeriod.getDate());
    const endDate = new Date(endPeriod.getFullYear(), endPeriod.getMonth(), endPeriod.getDate());

    let matchCount = 0;
    while (cur <= endDate) {
      if (cur < new Date(baseStart.getFullYear(), baseStart.getMonth(), baseStart.getDate())) {
        cur.setDate(cur.getDate() + 1);
        continue;
      }
      if (until && cur > until) break;

      const dayOfWeek = cur.getDay();
      let matches = false;

      if (freq === 'DAILY') {
        matches = true;
      } else if (freq === 'WEEKLY') {
        if (byDay) {
          matches = byDay.some(code => DAY_MAP[code] === dayOfWeek);
        } else {
          matches = (dayOfWeek === baseStart.getDay());
        }
      } else if (freq === 'MONTHLY') {
        matches = (cur.getDate() === baseStart.getDate());
      }

      if (matches) {
        matchCount++;
        if (count && matchCount > count) break;

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
          ...evt,
          start: instStart,
          end: instEnd
        });
      }

      cur.setDate(cur.getDate() + 1);
    }

    return instances;
  }

  function deduplicateEvents(events) {
    const seen = new Set();
    return events.filter(e => {
      if (!e.start) return false;
      const key = `${e.summary || ''}_${e.start.getTime()}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  function unescapeIcs(str) {
    return str
      .replace(/\\n/gi, '\n')
      .replace(/\\,/g, ',')
      .replace(/\\;/g, ';')
      .replace(/\\\\/g, '\\');
  }

  function parseIcsDate(str) {
    if (!str) return null;
    str = str.trim();

    // Date-only: YYYYMMDD
    if (str.length === 8 && /^\d{8}$/.test(str)) {
      const y = parseInt(str.substring(0, 4), 10);
      const m = parseInt(str.substring(4, 6), 10) - 1;
      const d = parseInt(str.substring(6, 8), 10);
      return new Date(y, m, d, 0, 0, 0);
    }

    // YYYYMMDDTHHMMSS or YYYYMMDDTHHMMSSZ
    const match = str.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?/);
    if (match) {
      const [, y, mo, d, h, mi, s, isUtc] = match;
      if (isUtc) {
        return new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +s));
      }
      return new Date(+y, +mo - 1, +d, +h, +mi, +s);
    }

    const fallback = new Date(str);
    return isNaN(fallback.getTime()) ? null : fallback;
  }

  // Meeting URL extraction
  const MEETING_REGEX = /https?:\/\/(?:[a-zA-Z0-9-]+\.)?(?:zoom\.us\/j\/\S+|meet\.google\.com\/\S+|teams\.microsoft\.com\/l\/meetup-join\/\S+|webex\.com\/\S+|meet\.jit\.si\/\S+)/i;

  function findMeetingLink(evt) {
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

  function getMeetingPlatform(url) {
    if (!url) return null;
    if (url.includes('meet.google.com')) return 'Google Meet';
    if (url.includes('zoom.us')) return 'Zoom';
    if (url.includes('teams.microsoft.com')) return 'Teams';
    if (url.includes('webex.com')) return 'Webex';
    if (url.includes('jit.si')) return 'Jitsi';
    return 'Meeting Call';
  }

  async function refreshCalendars() {
    const urls = getUrls();
    if (urls.length === 0) {
      configPanel.classList.add('open');
      eventsContainer.innerHTML = `
        <div class="empty-state">
          <p>No calendar feeds configured yet.</p>
          <p style="font-size: 11px;">Paste your Google Calendar, iCloud, or Outlook iCal URL above and click <b>Save Feeds</b>.</p>
        </div>
      `;
      return;
    }

    syncStatus.textContent = 'Syncing...';
    try {
      const results = await Promise.allSettled(urls.map(url => asyarFetch(url).then(parseIcs)));
      const events = [];
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
        throw results[0].reason || new Error('Failed to load calendar');
      }

      allEvents = deduplicateEvents(events.filter(e => e.start != null));
      localStorage.setItem('agenda_cached_events', JSON.stringify(allEvents));
      syncStatus.textContent = `Updated (${allEvents.length} events)`;
      setTimeout(() => { syncStatus.textContent = ''; }, 3000);
      render();
    } catch (err) {
      syncStatus.textContent = 'Sync error';
      console.error('Refresh error:', err);
      setTimeout(() => { syncStatus.textContent = ''; }, 4000);
      if (allEvents.length === 0) {
        eventsContainer.innerHTML = `
          <div class="empty-state">
            <p>Could not load calendar feed: ${escapeHtml(err.message || String(err))}</p>
            <p style="font-size: 11px;">Click ⚙️ Feeds to verify your iCal / ICS URL.</p>
          </div>
        `;
      }
    }
  }

  function formatTime(d) {
    if (!d) return '';
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function render() {
    const currentTime = new Date();
    const startOfToday = new Date(currentTime.getFullYear(), currentTime.getMonth(), currentTime.getDate());
    const sevenDaysLater = new Date(startOfToday.getTime() + 8 * 24 * 60 * 60 * 1000);

    let filtered = allEvents.filter(e => {
      if (!e.start) return false;
      if (e.end && e.end < startOfToday) return false;
      if (!e.end && e.start < startOfToday) return false;
      if (e.start > sevenDaysLater) return false;

      if (filterText) {
        const titleMatch = (e.summary || '').toLowerCase().includes(filterText);
        const locMatch = (e.location || '').toLowerCase().includes(filterText);
        return titleMatch || locMatch;
      }
      return true;
    });

    filtered.sort((a, b) => a.start - b.start);

    if (filtered.length === 0) {
      eventsContainer.innerHTML = `
        <div class="empty-state">
          <p>No upcoming events found for this week.</p>
        </div>
      `;
      return;
    }

    // Buckets
    const happeningNow = [];
    const today = [];
    const tomorrow = [];
    const later = [];

    const startOfTomorrow = new Date(startOfToday.getTime() + 24 * 60 * 60 * 1000);
    const startOfDayAfter = new Date(startOfTomorrow.getTime() + 24 * 60 * 60 * 1000);

    for (const evt of filtered) {
      const isNow = evt.start <= currentTime && evt.end && evt.end > currentTime;
      if (isNow) {
        happeningNow.push(evt);
      } else if (evt.start >= startOfToday && evt.start < startOfTomorrow) {
        today.push(evt);
      } else if (evt.start >= startOfTomorrow && evt.start < startOfDayAfter) {
        tomorrow.push(evt);
      } else {
        later.push(evt);
      }
    }

    let html = '';

    function renderGroup(title, list, isNowGroup = false) {
      if (list.length === 0) return '';
      let out = `<div class="section-title">${title} (${list.length})</div>`;
      for (const evt of list) {
        const meetingUrl = findMeetingLink(evt);
        const meetingName = getMeetingPlatform(meetingUrl);
        const isNow = isNowGroup || (evt.start <= currentTime && evt.end && evt.end > currentTime);
        const isPast = evt.end && evt.end < currentTime;

        let timeStr = '';
        if (evt.isAllDay) {
          timeStr = 'All day';
        } else {
          timeStr = `${formatTime(evt.start)} - ${formatTime(evt.end)}`;
        }

        let badge = '';
        if (isNow) {
          badge = `<span class="event-badge badge-now">Happening Now</span>`;
        } else if (isPast) {
          badge = `<span class="event-badge" style="opacity: 0.6;">Finished</span>`;
        } else if (evt.start > currentTime && (evt.start - currentTime) < 60 * 60 * 1000) {
          const mins = Math.round((evt.start - currentTime) / (60 * 1000));
          badge = `<span class="event-badge badge-soon">In ${mins}m</span>`;
        }

        let joinButton = '';
        if (meetingUrl && !isPast) {
          joinButton = `<button class="join-btn" data-url="${escapeHtml(meetingUrl)}" onclick="event.stopPropagation(); window.open('${escapeHtml(meetingUrl)}', '_blank');">Join ${meetingName}</button>`;
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

    html += renderGroup('⚡ Happening Now', happeningNow, true);
    html += renderGroup('Today', today);
    html += renderGroup('Tomorrow', tomorrow);
    html += renderGroup('This Week', later);

    eventsContainer.innerHTML = html;

    // Attach card click handlers
    eventsContainer.querySelectorAll('.event-card').forEach(card => {
      card.addEventListener('click', () => {
        const target = card.getAttribute('data-target');
        if (target) {
          window.open(target, '_blank');
        }
      });
    });
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  // Load cached events immediately if available
  const cached = localStorage.getItem('agenda_cached_events');
  if (cached) {
    try {
      allEvents = JSON.parse(cached).map(e => ({
        ...e,
        start: e.start ? new Date(e.start) : null,
        end: e.end ? new Date(e.end) : null,
      }));
      render();
    } catch (e) {}
  }

  // Initial refresh
  refreshCalendars();
  // Auto refresh every 5 minutes
  setInterval(refreshCalendars, 5 * 60 * 1000);
})();
