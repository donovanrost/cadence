import { shallowReactive } from "vue";
/** Opaque, owner-decoded drafts survive page navigation within this host session. */
export function createSettingsDrafts() {
  const drafts = shallowReactive(new Map<string, unknown>());
  return {
    get: (key: string) => drafts.get(key),
    dirty: (key: string) => drafts.has(key),
    retain(key: string, value: unknown, dirty: boolean) {
      if (dirty) drafts.set(key, value);
      else drafts.delete(key);
    },
    hasUnsaved: () => drafts.size > 0,
    clear: () => drafts.clear(),
  };
}
export type SettingsDrafts = ReturnType<typeof createSettingsDrafts>;
