import { decoders as d, perItem, type Unshown } from "@/api/index.ts";

/**
 * GET /passes (M7 / S1), read pass by pass (lead, ux U86 follow-up): a pass this console can't read
 * is left out and described (kind, id), so the schedule still shows the rest, with U86's line.
 */
export function passListReader<P>(pass: d.Reader<P>) {
  const shape = d.object({
    from: d.timestamp,
    to: d.timestamp,
    truncated: d.boolean,
    passes: perItem(pass, 500, { label: "Passes", kindOf: (raw) => [raw["kind"]] }),
  });
  return (
    value: unknown,
    path = "",
  ): Readonly<{
    from: string;
    to: string;
    truncated: boolean;
    passes: readonly P[];
    /** U86: the passes left out, for the line at the top of each list of them. */
    unshown: readonly Unshown[];
  }> => {
    const r = shape(value, path);
    return { ...r, passes: r.passes.items, unshown: r.passes.unshown };
  };
}
