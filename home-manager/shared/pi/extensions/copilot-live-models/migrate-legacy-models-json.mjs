import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const filePath = process.argv[2];
if (!filePath) throw new Error("models.json path is required");

let modelsJson;
try {
  modelsJson = JSON.parse(await fs.readFile(filePath, "utf8"));
} catch (error) {
  if (error?.code === "ENOENT") process.exit(0);
  process.exit(0);
}

const providers = modelsJson?.providers;
const copilot = providers?.["github-copilot"];
if (copilot?.name !== "GitHub Copilot (live catalog)") process.exit(0);

delete providers["github-copilot"];
if (Object.keys(providers).length === 0 && Object.keys(modelsJson).length === 1) {
  await fs.unlink(filePath);
  process.exit(0);
}

const tempPath = path.join(
  path.dirname(filePath),
  `.${path.basename(filePath)}.${process.pid}.${randomUUID()}.tmp`,
);
try {
  await fs.writeFile(tempPath, `${JSON.stringify(modelsJson, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  await fs.rename(tempPath, filePath);
} finally {
  await fs.unlink(tempPath).catch(() => undefined);
}
