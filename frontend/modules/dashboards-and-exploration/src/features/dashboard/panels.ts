import type { WorkspacePlacement } from "../workspace/contracts";

/** The one side sheet open at a time. A null id means "create". */
export type Panel =
  | { kind: "widget"; id: string | null }
  | { kind: "section"; id: string | null }
  | { kind: "details" }
  | { kind: "inspect"; placement: WorkspacePlacement };
