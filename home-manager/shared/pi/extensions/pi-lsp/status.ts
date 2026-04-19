import type { LspFailureInfo, ServerStatus, SupportedLanguage } from "./types.js";

function formatDurationFrom(startedAt: number | undefined): string {
  if (!startedAt) return "n/a";
  const seconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000));
  return `${seconds}s`;
}

function formatFailure(failure: LspFailureInfo | undefined): string | undefined {
  if (!failure) return undefined;
  const secondsAgo = Math.max(0, Math.round((Date.now() - failure.at) / 1000));
  const method = failure.method ? ` (${failure.method})` : "";
  return `${failure.category}${method}: ${failure.message} (${secondsAgo}s ago)`;
}

function formatRequest(status: ServerStatus): string | undefined {
  if (!status.lastRequest) return undefined;
  const outcome = status.lastRequest.ok ? "ok" : `error: ${status.lastRequest.error ?? "unknown"}`;
  return `${status.lastRequest.method} ${outcome} in ${status.lastRequest.durationMs}ms`;
}

export function formatStatusDetails(options: {
  statuses: ServerStatus[];
  configuredLanguages: SupportedLanguage[];
  configPath: string;
  configError?: string;
}): string {
  const { statuses, configuredLanguages, configPath, configError } = options;

  if (statuses.length === 0) {
    const configured = configuredLanguages.length > 0 ? configuredLanguages.join(", ") : "none";
    const lines = [
      `No tracked language server runtimes.`,
      `Configured languages: ${configured}`,
      `Config: ${configPath}`,
    ];
    if (configError) lines.push(`Config status: ${configError}`);
    return lines.join("\n");
  }

  return [
    `Language server runtimes (${statuses.length}):`,
    ...statuses.flatMap((status, index) => {
      const pid = status.pid ? ` pid ${status.pid}` : "";
      const lines = [
        `${index + 1}. ${status.language} — ${status.state}${pid}`,
        `   root: ${status.root}`,
        `   open docs: ${status.openDocuments} | uptime: ${formatDurationFrom(status.startedAt)} | restarts: ${status.restartCount}`,
      ];

      if (status.initializedAt) {
        lines.push(`   initialized: ${formatDurationFrom(status.initializedAt)} ago`);
      }
      if (status.readyAt) {
        lines.push(`   ready: ${formatDurationFrom(status.readyAt)} ago`);
      }

      const request = formatRequest(status);
      if (request) lines.push(`   last request: ${request}`);

      const failure = formatFailure(status.lastFailure);
      if (failure) lines.push(`   last failure: ${failure}`);

      if (status.lastStderrLines.length > 0) {
        lines.push(`   recent stderr:`);
        for (const line of status.lastStderrLines.slice(-3)) {
          lines.push(`     - ${line}`);
        }
      }

      return lines;
    }),
    `Config: ${configPath}`,
  ].join("\n");
}

export function formatLogDetails(options: {
  statuses: ServerStatus[];
  logs: string[];
  configPath: string;
}): string {
  const { statuses, logs, configPath } = options;

  const lines = [
    `LSP log view`,
    `Tracked runtimes: ${statuses.length}`,
  ];

  if (statuses.length > 0) {
    lines.push(
      ...statuses.map((status, index) => `${index + 1}. ${status.language} — ${status.state} — ${status.root}`),
      "",
    );
  }

  if (logs.length === 0) {
    lines.push("No recent lifecycle or stderr log lines.");
  } else {
    lines.push("Recent lifecycle and stderr lines:");
    for (const line of logs.slice(-30)) {
      lines.push(`- ${line}`);
    }
  }

  lines.push("", `Config: ${configPath}`);
  return lines.join("\n");
}
