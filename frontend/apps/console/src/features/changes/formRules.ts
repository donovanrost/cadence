import type { FormValues, KindSchema } from "./kindSchema.ts";

export type Change = Readonly<{ path: string; value: unknown }>;

/** Where a kind's form stands: its schema, the stored values, and the edited ones. */
export type FormState = Readonly<{ schema: KindSchema; before: FormValues; values: FormValues }>;

/**
 * Kind-specific form rules the schema can't say (U83: a transport's listener). Every one is
 * optional; the generic form works without them.
 */
export type FormRules = Readonly<{
  /** The edited values after each edit, adjusted (a hidden setting goes back to its default). */
  reconcile?: (state: FormState) => FormValues;
  /** The changes to stage, from the visible-field diff (add or drop what the diff can't see). */
  finish?: (changes: readonly Change[], state: FormState) => readonly Change[];
  /** Info lines under fields, by field path. */
  notes?: (state: FormState) => Readonly<Record<string, string>>;
  /** One change in the stage summary, or null for the generic `path → value`. */
  describe?: (change: Change, state: FormState) => string | null;
}>;
