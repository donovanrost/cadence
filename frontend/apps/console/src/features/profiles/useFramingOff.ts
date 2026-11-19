import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchSettings, profileFramingOff } from "@/features/settings/index.ts";

/** Whether this mission keeps profile framing out of the runtime (ST1, #45); read on Framing only. */
export function useFramingOff(
  missionId: Readonly<Ref<string>>,
  section: Readonly<Ref<string | null>>,
) {
  const settings = useRemoteQuery(
    () => (section.value === "framing" ? { kind: "mission" as const, id: missionId.value } : null),
    fetchSettings,
  );
  return computed(
    () => settings.state.value.status === "ready" && profileFramingOff(settings.state.value.value),
  );
}
