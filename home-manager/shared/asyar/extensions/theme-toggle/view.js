(function () {
  const EXTENSION_ID = 'org.asyar.theme-toggle';

  // Inform Asyar host that view is loaded
  try {
    window.parent.postMessage({ type: 'asyar:extension:loaded', extensionId: EXTENSION_ID, role: 'view' }, '*');
  } catch (e) {
    console.error('Failed to notify host:', e);
  }

  // Adopt host theme variables
  window.addEventListener('message', (event) => {
    if (event.data?.type === 'asyar:theme:variables' && event.data?.payload) {
      const vars = event.data.payload;
      for (const [k, v] of Object.entries(vars)) {
        document.documentElement.style.setProperty(k, v);
      }
    }
  });

  const isMac = navigator.userAgent.includes('Mac');
  const themeIcon = document.getElementById('theme-icon');
  const themeTitle = document.getElementById('theme-title');
  const themeStatus = document.getElementById('theme-status');
  const btnToggle = document.getElementById('btn-toggle');
  const btnDark = document.getElementById('btn-dark');
  const btnLight = document.getElementById('btn-light');

  function spawnShell(program, args) {
    return new Promise((resolve, reject) => {
      const spawnId = crypto.randomUUID();
      let stdout = '';

      const onMessage = (event) => {
        const msg = event.data;
        if (msg?.type !== 'asyar:stream' || msg?.streamId !== spawnId) return;

        if (msg.phase === 'chunk' && msg.data?.text) {
          stdout += msg.data.text;
        } else if (msg.phase === 'done') {
          window.removeEventListener('message', onMessage);
          resolve(stdout.trim());
        } else if (msg.phase === 'error') {
          window.removeEventListener('message', onMessage);
          reject(new Error(msg.data?.error?.message || 'Shell execution failed'));
        }
      };

      window.addEventListener('message', onMessage);

      try {
        window.parent.postMessage({
          type: 'asyar:api:shell:spawn',
          payload: { program, args, spawnId },
          messageId: crypto.randomUUID()
        }, '*');
      } catch (err) {
        window.removeEventListener('message', onMessage);
        reject(err);
      }

      // Safety timeout after 4s
      setTimeout(() => {
        window.removeEventListener('message', onMessage);
        resolve('timeout');
      }, 4000);
    });
  }

  async function applyTheme(mode) {
    try {
      if (mode === 'dark') {
        themeIcon.textContent = '🌙';
        themeTitle.textContent = 'Switching to Dark Mode';
        themeStatus.textContent = 'Applying dark theme...';
        if (isMac) {
          await spawnShell('osascript', ['-e', 'tell app "System Events" to tell appearance preferences to set dark mode to true']);
        } else {
          await spawnShell('darkman', ['set', 'dark']);
        }
      } else if (mode === 'light') {
        themeIcon.textContent = '☀️';
        themeTitle.textContent = 'Switching to Light Mode';
        themeStatus.textContent = 'Applying light theme...';
        if (isMac) {
          await spawnShell('osascript', ['-e', 'tell app "System Events" to tell appearance preferences to set dark mode to false']);
        } else {
          await spawnShell('darkman', ['set', 'light']);
        }
      } else {
        themeIcon.textContent = '🌓';
        themeTitle.textContent = 'Toggling Theme';
        themeStatus.textContent = 'Switching appearance...';
        if (isMac) {
          await spawnShell('osascript', ['-e', 'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode']);
        } else {
          await spawnShell('darkman', ['toggle']);
        }
      }

      themeStatus.textContent = 'Theme updated!';
      // Dismiss launcher window after brief confirmation
      setTimeout(() => {
        window.parent.postMessage({ type: 'asyar:window:hide' }, '*');
      }, 350);
    } catch (err) {
      console.error('Failed to switch theme:', err);
      themeTitle.textContent = 'Theme Switch Failed';
      themeStatus.textContent = err.message || String(err);
    }
  }

  btnToggle.addEventListener('click', () => applyTheme('toggle'));
  btnDark.addEventListener('click', () => applyTheme('dark'));
  btnLight.addEventListener('click', () => applyTheme('light'));

  // Auto-run on launch based on view param
  const urlParams = new URLSearchParams(window.location.search);
  const viewAction = urlParams.get('view') || 'toggle';
  applyTheme(viewAction);
})();
