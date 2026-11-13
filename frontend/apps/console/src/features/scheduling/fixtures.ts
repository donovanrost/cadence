import type { PlanPass } from "./api.ts";

type Booking = NonNullable<PlanPass["booking"]>;

/** Test fixture: a pass booking with every optional key present (decoded types require them). */
export function booking(
  state: Booking["state"],
  reason: string | null = null,
  extra: Partial<Booking> = {},
): Booking {
  return {
    state,
    reason,
    at: null,
    detail: null,
    retryable: null,
    retry_after_seconds: null,
    resolved: null,
    ...extra,
  };
}
