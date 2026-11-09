<script setup lang="ts">
import { computed } from "vue";
import type { ApiError, RemoteState } from "@/api";
import { ApButton, ApCallout, ApCheckRows, ApPanel, ApRemote, plural, type ApCheckRow } from "@/ui";
import { humanize, itemLine, type Preview } from "./actions.ts";

/** K2 Checks: the server's dry run of the staged set (validation, conflicts; more kinds in P2). */
const props = defineProps<{ preview: RemoteState<Preview> }>();
defineEmits<{ retry: [] }>();

const labels: Readonly<Record<string, string>> = {
  validation: "Validation",
  conflicts: "Conflicts",
};

function rows(preview: Preview): readonly ApCheckRow[] {
  return preview.checks.map((check) => ({
    key: check.key,
    label: labels[check.key] ?? humanize(check.key),
    sentence:
      check.items.length === 0
        ? check.key === "conflicts"
          ? "Every change applies cleanly on the live revision"
          : check.key === "compatibility"
            ? "Profile framing matches every transport's ingress"
            : "Every change is valid"
        : `${plural(check.items.length, "problem")}`,
    detail: check.items.map(itemLine).slice(0, 5).join(" · "),
    ...(check.verdict === "go"
      ? { state: "nominal" as const, verdict: "GO" }
      : check.verdict === "hold"
        ? { state: "caution" as const, verdict: "HOLD" }
        : { state: "crit" as const, verdict: "NO-GO" }),
  }));
}
/** Say why checks didn't run, by cause (ux pass 2 #7). */
function failureText(error: ApiError): string {
  switch (error.kind) {
    case "not_found":
      return "Checks couldn't run: this change set was applied or discarded by someone else.";
    case "malformed":
      return "Checks ran, but the server's reply wasn't understood.";
    case "unavailable":
      return error.status === 0
        ? "Checks couldn't run: the connection dropped."
        : `Checks couldn't run: ${error.message}`;
    case "unauthenticated":
    case "forbidden":
    case "conflict":
    case "invalid":
      return `Checks couldn't run: ${"message" in error ? error.message : "sign in again."}`;
  }
}
const meta = computed(() =>
  props.preview.status === "ready"
    ? `Verdict ${props.preview.value.verdict.replace("_", "-")}`
    : undefined,
);
</script>

<template>
  <ApPanel index="K2" title="Checks" :meta="meta" flush>
    <ApCallout v-if="preview.status === 'failed'" tone="caution">
      {{ failureText(preview.error) }}
      <template #action
        ><ApButton size="compact" @click="$emit('retry')">Reload</ApButton></template
      >
    </ApCallout>
    <ApRemote v-else :state="preview" loading-label="Running checks…" @retry="$emit('retry')">
      <template #default="{ value }"><ApCheckRows :rows="rows(value)" /></template>
    </ApRemote>
  </ApPanel>
</template>
