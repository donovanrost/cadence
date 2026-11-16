<script setup lang="ts">
import { computed, watch } from "vue";
import type { ApiError, RemoteState } from "@/api";
import { ApButton, ApCallout, ApPanel, ApRemote, refocusFirst } from "@/ui";
import type { Preview } from "./actions.ts";
import ChecksBody from "./ChecksBody.vue";
import { checkingLine, heldLabel, RECHECK_FAILED, type HeldChecks } from "./checks-view.ts";

/**
 * K2 Checks: the server's dry run of the staged set (validation, conflicts; more kinds in P2).
 * ux B4: when the set's version moves, the previous run's rows stay, dimmed and named, under a
 * status line until the new ones replace them; the first load still reads "Running checks…".
 */
const props = withDefaults(
  defineProps<{
    preview: RemoteState<Preview>;
    /** The previous run, while this one is loading or failed (null on a first load; rollback). */
    held?: HeldChecks | null | undefined;
    /** "Checks done: …" once new results replace re-running ones. */
    done?: string | null | undefined;
    /** How many changes the set has now, for "Checking again: …". */
    nowCount?: number | undefined;
    leftBy?: string | undefined;
  }>(),
  { held: null, done: null, nowCount: 0 },
);
defineEmits<{ retry: [] }>();

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
const shown = computed(() =>
  props.preview.status === "ready" ? props.preview.value : (props.held?.preview ?? null),
);
/** The verdict line gives way to the status line while the checks re-run. */
const meta = computed(() =>
  props.preview.status === "ready"
    ? `Verdict ${props.preview.value.verdict.replace("_", "-")}`
    : undefined,
);
/** Always in the page (a live region must exist before it changes); visible only with text. */
const status = computed(() => {
  if (props.held) return props.preview.status === "failed" ? "" : checkingLine(props.nowCount);
  return props.done ?? "";
});
// A control that survives the swap keeps focus; one that didn't lands on K2's heading.
watch(
  () => [props.held !== null, props.preview.status],
  ([holding], [wasHolding]) => {
    if (holding === true || wasHolding === true)
      refocusFirst(document.querySelector<HTMLElement>("#checks h2"));
  },
  { flush: "post" },
);
</script>

<template>
  <ApPanel id="checks" index="K2" title="Checks" :meta="meta" flush>
    <p
      role="status"
      :class="status ? 'm-0 border-b border-hairline px-4 py-2.5 text-md text-readout' : 'sr-only'"
    >
      {{ status }}
    </p>
    <ApCallout v-if="preview.status === 'failed'" :tone="held ? 'crit' : 'caution'">
      {{ held ? RECHECK_FAILED : failureText(preview.error) }}
      <template #action
        ><ApButton size="compact" @click="$emit('retry')">{{
          held ? "Try again" : "Reload"
        }}</ApButton></template
      >
    </ApCallout>
    <p v-if="held" class="m-0 px-4 pt-2.5 text-sm text-text-3">{{ heldLabel(held) }}</p>
    <ChecksBody v-if="shown" :preview="shown" :dimmed="held !== null" :left-by="leftBy" />
    <ApRemote
      v-else-if="preview.status === 'loading'"
      :state="preview"
      loading-label="Running checks…"
      @retry="$emit('retry')"
    >
      <template #default />
    </ApRemote>
  </ApPanel>
</template>
