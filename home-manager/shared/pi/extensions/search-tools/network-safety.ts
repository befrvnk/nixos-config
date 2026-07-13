import { isIP } from "node:net";

function ipv4Value(address: string): number | undefined {
  if (isIP(address) !== 4) return undefined;
  return address.split(".").reduce((value, part) => (value * 256) + Number(part), 0) >>> 0;
}

function ipv4InCidr(value: number, base: string, prefix: number): boolean {
  const baseValue = ipv4Value(base)!;
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return (value & mask) === (baseValue & mask);
}

function ipv6Value(address: string): bigint | undefined {
  let normalized = address.toLowerCase().split("%")[0]!;
  const mappedMatch = normalized.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/u);
  if (mappedMatch) {
    const ipv4 = ipv4Value(mappedMatch[2]!);
    if (ipv4 === undefined) return undefined;
    normalized = `${mappedMatch[1]}${((ipv4 >>> 16) & 0xffff).toString(16)}:${(ipv4 & 0xffff).toString(16)}`;
  }
  if (isIP(normalized) !== 6 && !normalized.includes("::")) return undefined;

  const halves = normalized.split("::");
  if (halves.length > 2) return undefined;
  const left = halves[0] ? halves[0].split(":") : [];
  const right = halves[1] ? halves[1].split(":") : [];
  const missing = 8 - left.length - right.length;
  if (missing < 0 || (halves.length === 1 && missing !== 0)) return undefined;
  const parts = [...left, ...new Array(missing).fill("0"), ...right];
  if (parts.length !== 8 || parts.some((part) => !/^[0-9a-f]{1,4}$/u.test(part))) return undefined;
  return parts.reduce((value, part) => (value << 16n) | BigInt(Number.parseInt(part, 16)), 0n);
}

function ipv6InCidr(value: bigint, base: string, prefix: number): boolean {
  const baseValue = ipv6Value(base)!;
  const shift = BigInt(128 - prefix);
  return (value >> shift) === (baseValue >> shift);
}

const DENIED_IPV4: Array<[string, number]> = [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8],
  ["169.254.0.0", 16], ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24],
  ["192.88.99.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15], ["198.51.100.0", 24],
  ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
];

export function isPublicIpAddress(address: string): boolean {
  const ipv4 = ipv4Value(address);
  if (ipv4 !== undefined) return !DENIED_IPV4.some(([base, prefix]) => ipv4InCidr(ipv4, base, prefix));

  const ipv6 = ipv6Value(address);
  if (ipv6 === undefined) return false;
  if (ipv6InCidr(ipv6, "::ffff:0:0", 96)) {
    const mapped = Number(ipv6 & 0xffffffffn) >>> 0;
    return !DENIED_IPV4.some(([base, prefix]) => ipv4InCidr(mapped, base, prefix));
  }
  if (!ipv6InCidr(ipv6, "2000::", 3)) return false;
  return ![
    ["2001::", 23],
    ["2001:db8::", 32],
    ["2002::", 16],
    ["3fff::", 20],
  ].some(([base, prefix]) => ipv6InCidr(ipv6, base as string, prefix as number));
}

export function normalizeHostname(hostname: string): string {
  const normalized = hostname.trim().toLowerCase().replace(/\.$/u, "");
  return normalized.startsWith("[") && normalized.endsWith("]")
    ? normalized.slice(1, -1)
    : normalized;
}

export function isLocalHostname(hostname: string): boolean {
  return hostname === "localhost" || hostname.endsWith(".localhost");
}
