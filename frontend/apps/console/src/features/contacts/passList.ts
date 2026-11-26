import { decoders as d, perItem, type Decoded, type Unshown } from "@/api/index.ts";

/** The most passes one page carries (api #845: limit up to 500). */
export const PASS_PAGE_LIMIT = 500;

/**
 * Whole-window counts on every page of GET /passes (#793, api #845): the numbers a screen shows
 * come from here, never from counting the rows it holds.
 */
export const passCountsReader = d.object({
  total: d.integer,
  booked: d.integer,
  hand_started: d.integer,
  /** Distinct spacecraft with a live booking now. */
  in_contact: d.integer,
  /** Confirmed or active bookings that start after server time. */
  upcoming: d.integer,
  synthetic: d.integer,
});
export type PassCounts = Decoded<typeof passCountsReader>;

/**
 * One page of GET /passes (M7 / S1), read pass by pass (lead, ux U86 follow-up): a pass this console
 * can't read is left out and described (kind, id), so the schedule still shows the rest, with
 * U86's line.
 */
export function passPageReader<P>(pass: d.Reader<P>) {
  const shape = d.object({
    from: d.timestamp,
    to: d.timestamp,
    counts: passCountsReader,
    passes: perItem(pass, PASS_PAGE_LIMIT, { label: "Passes", kindOf: (raw) => [raw["kind"]] }),
  });
  return (value: unknown, path = "") => {
    const r = shape(value, path);
    return { ...r, passes: r.passes.items, unshown: r.passes.unshown };
  };
}

/** Every pass in a window, walked page by page to the end (#793: no ceiling at any fleet size). */
export type PassWindow<P> = Readonly<{
  from: string;
  to: string;
  counts: PassCounts;
  passes: readonly P[];
  /** U86: the passes left out, for the line at the top of each list of them. */
  unshown: readonly Unshown[];
}>;
