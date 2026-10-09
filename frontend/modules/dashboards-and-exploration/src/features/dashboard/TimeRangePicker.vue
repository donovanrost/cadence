<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";
import CadenceDateTimeRangeField from "@cadence/ui/CadenceDateTimeRangeField.vue";
import type { UtcRange } from "@cadence/ui/date-time-range";
import {
  absoluteSelection,
  frozenRange,
  quickRanges,
  selectionLabel,
  type TimeSelection,
} from "./time-range";
import { readRecents, rememberRecent } from "./time-recents";

const props = defineProps<{ selection: TimeSelection; live: boolean; now: number }>();
const emit = defineEmits<{ select: [selection: TimeSelection] }>();

const absolute = ref<UtcRange | null>(null);
const error = ref("");
const max = computed(() => new Date(props.now).toISOString().slice(0, 19) + "Z");
const recents = ref<TimeSelection[]>([]);
const label = computed(() => selectionLabel(props.selection));
const isCurrent = (seconds: number) =>
  props.selection.kind === "sliding" && props.selection.seconds === seconds;

function opened() {
  absolute.value = frozenRange(props.selection, props.now);
  error.value = "";
  recents.value = readRecents();
}
function choose(selection: TimeSelection, close: () => void) {
  rememberRecent(selection);
  emit("select", selection);
  close();
}
function apply(close: () => void) {
  const parsed = absolute.value ? absoluteSelection(absolute.value) : "Choose a start and end.";
  if (typeof parsed === "string") error.value = parsed;
  else choose(parsed, close);
}
</script>

<template>
  <CadencePopover
    id="dashboard-time-range"
    identity="dashboard-time-range"
    class="cadence-overlay"
    :data-query-state="live ? 'live' : 'fixed'"
    align="start"
  >
    <template #trigger="{ open }">
      <button
        type="button"
        class="cadence-dashboard-query-trigger inline-flex items-center"
        data-overlay-trigger
        :aria-expanded="open"
        aria-haspopup="dialog"
        @click="!open && opened()"
      >
        <span class="cadence-dashboard-query-dot" aria-hidden="true"></span>
        <span class="cadence-dashboard-query-trigger-label">Time</span>
        <span class="cadence-dashboard-query-trigger-value">{{ label }}</span>
        <CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open, close }">
      <div
        class="cadence-overlay-panel cadence-popover-panel"
        data-overlay-width="lg"
        :hidden="!open"
        role="dialog"
        aria-label="Time range"
      >
        <div class="cadence-dashboard-query-panel-header">
          <span class="hud-label">Time range</span>
        </div>
        <div class="cadence-dashboard-query-panel-body grid gap-4 sm:grid-cols-[1fr_12rem]">
          <form class="cadence-dashboard-query-section space-y-2" @submit.prevent="apply(close)">
            <CadenceDateTimeRangeField
              id="dashboard-time-absolute"
              v-model="absolute"
              label="Absolute range"
              :max="max"
              v-bind="error ? { error } : {}"
            />
            <div class="flex gap-2">
              <CadenceButton type="submit" variant="primary" size="sm">Apply range</CadenceButton>
              <CadenceButton variant="quiet" size="sm" @click="choose({ kind: 'default' }, close)"
                >Dashboard default</CadenceButton
              >
            </div>
            <template v-if="recents.length">
              <p class="hud-label pt-2">Recent</p>
              <ul class="space-y-0.5">
                <li
                  v-for="recent in recents"
                  :key="JSON.stringify(recent)"
                  class="cadence-menu-item"
                >
                  <button type="button" @click="choose(recent, close)">
                    {{ selectionLabel(recent) }}
                  </button>
                </li>
              </ul>
            </template>
          </form>
          <ul class="space-y-0.5" aria-label="Quick ranges">
            <li v-for="range in quickRanges" :key="range.from" class="cadence-menu-item">
              <button
                type="button"
                :aria-pressed="isCurrent(range.seconds)"
                :class="isCurrent(range.seconds) ? 'text-primary' : ''"
                @click="choose({ kind: 'sliding', seconds: range.seconds }, close)"
              >
                {{ range.label }}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </template>
  </CadencePopover>
</template>
