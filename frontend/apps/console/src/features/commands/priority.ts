import { formatShort } from "@/ui";

/**
 * ux U68: command priority and expiry. Priority is 0..9, default 3, LOWER = SOONER, and it orders
 * only within one target's queue lane (api); the console offers Normal (3) and High (1), keeps a
 * low one on resend, and shows the number only in Technical details.
 */
export const PRIORITY_NORMAL = 3;
export const PRIORITY_HIGH = 1;
export const PRIORITY_HINT =
  "High-priority uplinks go before normal ones queued for the same spacecraft.";

/** Normal is silent; anything below reads HIGH PRIORITY, anything above LOW PRIORITY. */
export function priorityTag(priority: number | null | undefined): string | null {
  if (priority === null || priority === undefined || priority === PRIORITY_NORMAL) return null;
  return priority < PRIORITY_NORMAL ? "HIGH PRIORITY" : "LOW PRIORITY";
}

/** Normal · High, plus 'Low (as before)' when a resend carries a low one (never changed quietly). */
export function priorityChoices(current: number): { value: string; label: string }[] {
  const choices = [
    { value: String(PRIORITY_NORMAL), label: "Normal" },
    { value: String(PRIORITY_HIGH), label: "High" },
  ];
  if (current > PRIORITY_NORMAL) choices.push({ value: String(current), label: "Low (as before)" });
  return choices;
}

/** Compose's expiry refusals (ux U68); null when it's fine or not set. */
export function expiryProblem(
  expiresAt: number | null,
  notBefore: number | null,
  now: number,
): string | null {
  if (expiresAt === null) return null;
  if (expiresAt <= now) return "Pick a time in the future.";
  if (notBefore !== null && expiresAt <= notBefore)
    return `Pick a time after the hold time, ${formatShort(new Date(notBefore))}.`;
  return null;
}

/** 'Expires 11-16 04:00Z' on Approve and the request's Release line. */
export const expiresWords = (iso: string) => `Expires ${formatShort(new Date(iso))}`;
