import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { saveSection, type SettingsScope, type SettingsSection } from "./api.ts";

/** Direct save of one settings section (201, active); U20 wording on failure. */
export function useSectionSave(
  scope: () => SettingsScope,
  section: () => SettingsSection,
  onSaved: () => void,
) {
  const busy = ref(false);
  const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);

  /** `outcome` writes the whole line from the new version (ux: a Reset names the value it had). */
  async function save(
    values: Readonly<Record<string, unknown>>,
    what = "Saved",
    outcome?: (version: number) => string,
  ) {
    if (busy.value) return;
    busy.value = true;
    try {
      const result = await saveSection(scope(), section().key, {
        values,
        expected_version: section().version?.version ?? null,
      });
      note.value = result.ok
        ? {
            tone: "nominal",
            text: outcome
              ? outcome(result.value.version)
              : `${what} as v${result.value.version}. It's active now.`,
          }
        : { tone: "crit", text: failureOutcome(result.error, "changed").sentence };
      if (result.ok) onSaved();
    } finally {
      busy.value = false;
    }
  }
  return { busy, note, save };
}
