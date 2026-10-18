/** Editable text, including incomplete input, stays separate from serialized command intent. */
export type ArgumentEditorDraft = {
  /** Undefined means not yet entered; an empty string is an explicit text value. */
  values: Record<string, string | undefined>;
};
