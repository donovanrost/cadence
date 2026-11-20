<script setup lang="ts">
import { computed, watch } from "vue";
import { ApButton, ApCallout, formatClock, refocusFirst } from "@/ui";
import type { SkippedEvent } from "./contracts.ts";
import type { Conflict, Notice } from "./useEditSession.ts";

/**
 * Edit-mode callouts: someone saved meanwhile (Continue editing / Discard mine), plus the
 * session's latest notice (a refused edit, edits that no longer apply, the command cap).
 */
const props = defineProps<{
  conflict: Conflict | null;
  notice: Notice | null;
  busy: boolean;
  resumed: boolean;
  /** The board places a retired library item (after a restore): say it before Save refuses. */
  retiredLibrary: boolean;
}>();
const emit = defineEmits<{ continue: []; discardMine: [] }>();
/** A5: Continue editing and Discard mine take the callout, and the focused button, with them. */
watch(
  () => props.conflict,
  (now, was) => {
    if (was && !now) refocusFirst();
  },
  { flush: "post" },
);
const savedLine = computed(() => {
  const c = props.conflict;
  if (!c) return "";
  const who = c.savedBy ?? "Someone";
  const at = c.savedAt ? ` at ${formatClock(new Date(c.savedAt)).slice(0, 5)}Z` : "";
  return `Saved by ${who}${at} while you were editing (now v${c.currentVersion}).`;
});
const EVENT_LABEL: Readonly<Record<SkippedEvent, string>> = {
  update_widget: "Update widget",
  remove_widget: "Remove widget",
  add_library_widget: "Add library widget",
  add_widget: "Add widget",
  layout: "Move or resize",
  add_section: "Add section",
  update_section: "Update section",
  remove_section: "Remove section",
  move_section: "Move section",
  rename: "Rename",
  runtime_defaults: "Defaults",
  unrecognized: "Another edit",
};
const noticeText = computed(() => {
  const n = props.notice;
  if (!n) return null;
  switch (n.kind) {
    case "rejected":
    case "failed":
      return n.message;
    case "skipped":
      return `${n.events.length} ${n.events.length === 1 ? "edit no longer applies" : "edits no longer apply"}: ${n.events.map((e) => EVENT_LABEL[e]).join(", ")}.`;
    case "too_many_commands":
      return "Save to keep going. This draft has as many changes as one save can take.";
    case "not_ready":
      // One message per distinct reason: three widgets on one unavailable source say it once (qa).
      return `Not saved: ${[...new Set(n.placements.map((p) => p.message))].join(" ")}`;
  }
  return null;
});
</script>

<template>
  <ApCallout v-if="conflict" tone="caution">
    {{ savedLine }}
    <template #action>
      <span class="flex gap-2">
        <ApButton
          size="compact"
          variant="primary"
          :disabled="busy"
          disabled-reason="Working…"
          @click="emit('continue')"
          >Continue editing</ApButton
        >
        <ApButton size="compact" variant="secondary" @click="emit('discardMine')"
          >Discard mine</ApButton
        >
      </span>
    </template>
  </ApCallout>
  <!-- Not alongside a notice: Save's refusal already says the same sentence. -->
  <ApCallout v-if="retiredLibrary && !noticeText" tone="caution"
    >That library widget was retired or removed. Remove it from this dashboard to save.</ApCallout
  >
  <ApCallout
    v-if="noticeText"
    :tone="notice?.kind === 'skipped' || notice?.kind === 'too_many_commands' ? 'caution' : 'crit'"
    role="alert"
  >
    {{ noticeText }}
  </ApCallout>
  <ApCallout v-else-if="resumed" tone="info"
    >Resumed your unsaved edits from this browser.</ApCallout
  >
</template>
