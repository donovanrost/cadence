import type { ApiError } from "@/api/index.ts";
import { invalidOpDetails } from "./actions.ts";

/**
 * A rejected stage's field errors, split for a form (U79: the error sits on its field): those whose
 * path is one of the form's fields, and the rest (shown in the form's callout).
 */
export function fieldErrors(
  error: ApiError,
  paths: ReadonlySet<string>,
  /** The op the form staged (a KindEditor stages one, at 0); another op's errors stay in the rest. */
  index = 0,
): Readonly<{
  onFields: Readonly<Record<string, string>>;
  rest: readonly Readonly<{ path: string; message: string }>[];
}> | null {
  const detail = invalidOpDetails(error);
  if (!detail || detail.errors.length === 0) return null;
  const onFields: Record<string, string> = {};
  const rest: { path: string; message: string }[] = [];
  for (const e of detail.errors) {
    // compared-as-text: the kinds send plain field paths, the schema's own (fe-setup); first message wins.
    if (detail.index === index && paths.has(e.path) && onFields[e.path] === undefined)
      onFields[e.path] = e.message;
    else rest.push(e);
  }
  return { onFields, rest };
}
