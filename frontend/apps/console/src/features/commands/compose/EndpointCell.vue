<script setup lang="ts">
import { computed } from "vue";
import { ApSelect, ApTag } from "@/ui";
import type { TargetEndpoints } from "../groups/api.ts";

/**
 * C4 endpoint for one target (DECISIONS #41): what routing resolves, or why it can't, and an
 * explicit override (audited on the group) when the operator picks an endpoint.
 */
const props = defineProps<{
  name: string;
  info: TargetEndpoints | undefined;
  override: string | undefined;
}>();
const emit = defineEmits<{ change: [endpointId: string | null] }>();

const FAILURE_WORDS: Readonly<Record<string, string>> = {
  no_uplink_route: "No uplink route",
  multiple_primary_uplink_routes: "Several primary uplink routes",
};
const label = (e: TargetEndpoints["endpoints"][number]) =>
  `${e.name ?? e.id}${e.managed ? " · routes" : ""}`;
const options = computed(() => [
  { value: "", label: "Use routing" },
  ...(props.info?.endpoints ?? []).map((e) => ({ value: e.id, label: label(e) })),
]);
const resolved = computed(() => {
  const id = props.info?.resolved_source_endpoint_id;
  return id ? (props.info?.endpoints.find((e) => e.id === id)?.name ?? id) : null;
});
const choice = computed({
  get: () => props.override ?? "",
  set: (v: string) => emit("change", v === "" ? null : v),
});
</script>

<template>
  <span v-if="info" class="flex items-center justify-end gap-2">
    <ApTag v-if="override" state="caution" label="OVERRIDE" />
    <span v-else-if="resolved" class="font-mono text-sm text-text-3">via {{ resolved }}</span>
    <span v-else class="font-mono text-sm text-caution-text">{{
      FAILURE_WORDS[info.failure ?? ""] ?? "No uplink endpoint"
    }}</span>
    <ApSelect
      v-if="override || !resolved"
      v-model="choice"
      :label="`Uplink endpoint for ${name}`"
      hidden-label
      size="compact"
      mono
      :options="options"
    />
  </span>
</template>
