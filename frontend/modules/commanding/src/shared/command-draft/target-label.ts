import type { Target } from "./contracts";

export function targetLabel(target: Pick<Target, "name" | "scid">): string {
  return target.name?.trim() || (target.scid === null ? "Unnamed target" : `SCID ${target.scid}`);
}
