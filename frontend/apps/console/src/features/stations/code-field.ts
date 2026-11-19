import type { KindSchema } from "@/features/changes/index.ts";

/** ux U25: why an empty Code is fine while none is stored. */
export const CODE_HELP = "Leave empty to keep showing the station's name.";

/**
 * ux U25 (11-16): a station without a code is legitimate (every reader falls back to its name), so
 * while none is stored 'Code' is optional, and the 2–8 letter check applies only to what's typed.
 * Once a code is set it can be changed but not removed: the form makes it required, and the server
 * refuses an emptied code as a backstop (domain).
 */
export function withCodeRule(storedCode: string | null) {
  return (schema: KindSchema): KindSchema => ({
    ...schema,
    fields: schema.fields.map((f) => {
      // compared-as-text: a schema field path, an open set the server's schema defines
      if (f.path !== "code") return f;
      return storedCode ? { ...f, required: true } : { ...f, required: false, help: CODE_HELP };
    }),
  });
}

/** ux U25: the read's suggested code, offered as 'Suggested: INU' + 'Use INU' (staged with the edit). */
export const codeSuggestion = (suggested: string | null | undefined) =>
  suggested ? { path: "code", value: suggested } : null;
