import { decoders as d, type Decoded } from "@/api/index.ts";

/**
 * U75 (api be3fa592b): set once any member ended expired, on the group read and list rows.
 * sent = members that went out; total = member_count. Optional until it ships.
 */
export const expiryReader = d.optional(
  d.nullable(
    d.object({
      expires_at: d.timestamp,
      expired: d.integer,
      sent: d.integer,
      total: d.integer,
    }),
  ),
);
export type Expiry = NonNullable<Decoded<typeof expiryReader>>;

/** ux U75 list row: 'Expired · 2 of 5 sent', or 'Expired' when none went out. */
export const expiredRowLabel = (e: Expiry) =>
  e.sent > 0 ? `Expired · ${e.sent} of ${e.total} sent` : "Expired";
