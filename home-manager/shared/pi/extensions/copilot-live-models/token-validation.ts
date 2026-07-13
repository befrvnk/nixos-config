export function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

export function positiveSafeIntegerOr(value: unknown, fallback: number): number {
  return isPositiveSafeInteger(value) ? value : fallback;
}
