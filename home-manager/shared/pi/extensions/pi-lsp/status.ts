import type { ServerStatus, SupportedLanguage } from "./types.js";

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
      `No running language servers.`,
      `Configured languages: ${configured}`,
      `Config: ${configPath}`,
    ];
    if (configError) lines.push(`Config status: ${configError}`);
    return lines.join("\n");
  }

  return [
    `Running language servers (${statuses.length}):`,
    ...statuses.map((status, index) => {
      const uptimeSeconds = status.startedAt ? Math.max(0, Math.round((Date.now() - status.startedAt) / 1000)) : 0;
      const pid = status.pid ? ` pid ${status.pid}` : "";
      return `${index + 1}. ${status.language} — ${status.root} (${status.openDocuments} open docs, ${uptimeSeconds}s uptime${pid})`;
    }),
    `Config: ${configPath}`,
  ].join("\n");
}
