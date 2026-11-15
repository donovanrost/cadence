import { decode, stationRef, type StationRef } from "@/api/index.ts";
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

/** Test fixture: a station reference, decoded (the id is a StationId, §12C). */
export function station(raw: {
  ref: string | null;
  id: string | null;
  code: string | null;
  name: string | null;
}): StationRef {
  const r = decode(stationRef, raw);
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}
