import { plural } from "@/ui";

/**
 * ux U93: applying on a mission with no activation saves and starts nothing. Keyed only on the
 * server's has_active_configuration === false, never on runtime not_applicable (which also
 * covers changes the runtime doesn't use).
 */
export const NOTHING_RUNNING =
  "Nothing is running on this mission yet, so applying saves these changes and starts nothing. Each spacecraft starts when its configuration is reviewed and activated.";

/** After the apply: "r1 is saved, 2 changes. Nothing is running on this mission yet, so nothing started." */
export const savedOnlyText = (revision: number, changes: number) =>
  `r${revision} is saved, ${plural(changes, "change")}. Nothing is running on this mission yet, so nothing started.`;
