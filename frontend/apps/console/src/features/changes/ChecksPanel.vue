<script setup lang="ts">
import { computed } from "vue";
import type { ApiError, RemoteState } from "@/api";
import { ApButton, ApCallout, ApCheckRows, ApPanel, ApRemote, plural, type ApCheckRow } from "@/ui";
import { groupedLines, humanize, type Preview } from "./actions.ts";
import AlarmLinks from "./AlarmLinks.vue";
import DependentLinks from "./DependentLinks.vue";
import { dependents } from "./dependents.ts";
import { alarmPoints, appHolds, checkTitle } from "./holds.ts";
import AppInstallLinks from "./AppInstallLinks.vue";

/** K2 Checks: the server's dry run of the staged set (validation, conflicts; more kinds in P2). */
/** `leftBy` names what the conflict's base came from ("r8"), for the conflict sentence. */
const props = defineProps<{ preview: RemoteState<Preview>; leftBy?: string | undefined }>();
defineEmits<{ retry: [] }>();

const labels: Readonly<Record<string, string>> = {
  validation: "Validation",
  conflicts: "Conflicts",
};

function rows(preview: Preview): readonly ApCheckRow[] {
  return preview.checks.map((check) => ({
    key: check.key,
    label: checkTitle(check.items) ?? labels[check.key] ?? humanize(check.key),
    sentence:
      check.items.length === 0
        ? check.key === "conflicts"
          ? "Every change applies cleanly on the live revision"
          : check.key === "compatibility"
            ? "Profile framing matches every transport's ingress"
            : "Every change is valid"
        : plural(groupedLines(check.items).length, "problem"),
    detail: groupedLines(check.items, props.leftBy).slice(0, 5).join(" · "),
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
/** Raw comparisons behind the plain sentences (ux: machine detail goes to Technical details). */
const technical = computed(() =>
  props.preview.status === "ready"
    ? props.preview.value.checks.flatMap((c) =>
        c.items.flatMap((i) => (i.detail ? [i.detail] : [])),
      )
    : [],
);
const meta = computed(() =>
  props.preview.status === "ready"
    ? `Verdict ${props.preview.value.verdict.replace("_", "-")}`
    : undefined,
);
</script>

<template>
  <ApPanel id="checks" index="K2" title="Checks" :meta="meta" flush>
    <ApCallout v-if="preview.status === 'failed'" tone="caution">
      {{ failureText(preview.error) }}
      <template #action
        ><ApButton size="compact" @click="$emit('retry')">Reload</ApButton></template
      >
    </ApCallout>
    <ApRemote v-else :state="preview" loading-label="Running checks…" @retry="$emit('retry')">
      <template #default="{ value }">
        <ApCheckRows :rows="rows(value)" />
        <DependentLinks :points="dependents(value)" />
        <AlarmLinks :points="alarmPoints(value)" />
        <AppInstallLinks :holds="appHolds(value)" />
        <details v-if="technical.length > 0" class="border-t border-hairline px-4 py-2.5">
          <summary class="ap-label cursor-pointer">Technical details</summary>
          <ul class="m-0 mt-2 flex list-none flex-col gap-1 p-0 font-mono text-xs text-text-3">
            <li v-for="(t, i) in technical" :key="i">{{ t }}</li>
          </ul>
        </details>
      </template>
    </ApRemote>
  </ApPanel>
</template>
