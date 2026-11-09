<script setup lang="ts">
import { computed } from "vue";
import { describeApiError, type RemoteState } from "@/api/index.ts";
import { ApButton, ApCallout, ApCheckRows, ApEmptyState, ApPanel } from "@/ui";
import type { Preflight } from "../groups/api.ts";
import { checkMeta, checkRows, type TargetName } from "../groups/checks.ts";

/**
 * C3 · GO / NO-GO poll (Command.md): the server's preflight, re-run on every change. While it
 * re-checks, the last rows stay with `CHECKING…` verdicts so nothing reads as GO early.
 */
const props = defineProps<{
  state: RemoteState<Preflight>;
  checking: boolean;
  ready: boolean;
  nameOf: TargetName;
}>();
defineEmits<{ retry: [] }>();

const last = computed(() => (props.state.status === "ready" ? props.state.value : null));
const rows = computed(() => {
  const pf = last.value;
  if (!pf) return [];
  const all = checkRows(pf, props.nameOf);
  return props.checking
    ? all.map((r) => ({ ...r, state: "neutral" as const, verdict: "CHECKING…" }))
    : all;
});
/** The slot hands back an ApCheckRow, so look the link up by key. */
const rowProfile = (key: string) => rows.value.find((r) => r.key === key)?.profileId ?? null;
const meta = computed(() =>
  props.checking ? "checking…" : last.value ? checkMeta(last.value) : undefined,
);
</script>

<template>
  <ApPanel index="C3" title="GO / NO-GO poll" :meta="meta" flush>
    <ApEmptyState
      v-if="!ready"
      state="off"
      headline="Nothing to check yet"
      sentence="Add targets and valid commands; the server checks identity, catalog, conflicts, contact and two-person."
    />
    <ApCallout v-else-if="state.status === 'failed' && !checking" tone="caution">
      Couldn't run the checks: {{ describeApiError(state.error) }}
      <template #action
        ><ApButton size="compact" @click="$emit('retry')">Check again</ApButton></template
      >
    </ApCallout>
    <p v-else-if="rows.length === 0" class="m-0 px-4 py-3 font-mono text-sm text-text-3 uppercase">
      Checking…
    </p>
    <ApCheckRows v-else :rows="rows">
      <template v-if="rows.some((r) => r.profileId)" #action="{ row }">
        <ApButton
          v-if="rowProfile(row.key)"
          size="compact"
          :to="{
            name: 'setup.profile',
            params: { profileId: rowProfile(row.key), section: 'routing' },
          }"
          >Fix routing</ApButton
        >
      </template>
    </ApCheckRows>
  </ApPanel>
</template>
