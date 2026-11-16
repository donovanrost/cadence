<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { ApSegmented } from "@/ui";
import { severityFloors, type SeverityFloor } from "./api.ts";

/**
 * The Timeline's severity threshold (§11c(C) A9a; ux decisions U69, api 6790e4394): `All` ·
 * `Caution and up` · `Critical`, in the URL as `?severity=`. A threshold, not a multi-select; the
 * density strip stacks only what's shown (the reads pass `severity_at_least`).
 */
const route = useRoute();
const router = useRouter();
const options = [
  { value: "all", label: "All" },
  { value: "caution", label: "Caution and up" },
  { value: "critical", label: "Critical" },
] as const;
const value = computed<"all" | SeverityFloor>(() => {
  const raw = route.query["severity"];
  return severityFloors.find((f) => f === raw) ?? "all";
});
function set(next: string) {
  const floor = severityFloors.find((f) => f === next);
  router
    .replace({ query: { ...route.query, severity: floor } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
</script>

<template>
  <ApSegmented :model-value="value" :options="options" label="Severity" @update:model-value="set" />
</template>
