<script setup lang="ts">
import { computed } from "vue";
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";
import type { WorkspaceSnapshot } from "../workspace/contracts";
import type { ScopeOption } from "./contracts";
import { currentSelection, shift, zoomOut, type TimeSelection } from "./time-range";
import ScopePicker from "./ScopePicker.vue";
import TimeRangePicker from "./TimeRangePicker.vue";

const props = defineProps<{
  context: WorkspaceSnapshot["context"];
  scopeOptions: readonly ScopeOption[];
  spacecraft: string | null;
  liveCapable: boolean;
  paused: boolean;
  updatedAgo: string | null;
  now: number;
}>();
const emit = defineEmits<{
  time: [selection: TimeSelection];
  spacecraft: [id: string | null];
  pause: [];
}>();
const selection = computed(() => currentSelection(props.context));
const live = computed(() => props.liveCapable && !props.paused);
</script>

<template>
  <div
    class="cadence-dashboard-query-strip flex-wrap"
    role="toolbar"
    aria-label="Dashboard time and scope"
  >
    <CadenceIconButton
      icon="hero-chevron-left"
      label="Earlier"
      @click="emit('time', shift(selection, -1, now))"
    />
    <TimeRangePicker
      :selection="selection"
      :live="live"
      :now="now"
      @select="(s) => emit('time', s)"
    />
    <CadenceIconButton
      icon="hero-chevron-right"
      label="Later"
      :disabled="selection.kind !== 'absolute'"
      @click="emit('time', shift(selection, 1, now))"
    />
    <CadenceIconButton
      icon="hero-magnifying-glass-minus"
      label="Zoom out"
      @click="emit('time', zoomOut(selection, now))"
    />
    <span class="mx-1 h-4 border-l border-base-300" aria-hidden="true"></span>
    <ScopePicker
      :options="scopeOptions"
      :selected="spacecraft"
      @select="(id) => emit('spacecraft', id)"
    />
    <template v-if="liveCapable">
      <span class="mx-1 h-4 border-l border-base-300" aria-hidden="true"></span>
      <CadenceIconButton
        :icon="paused ? 'hero-play' : 'hero-pause'"
        :label="paused ? 'Resume live updates' : 'Pause live updates'"
        @click="emit('pause')"
      />
      <span class="font-mono text-xs text-base-content/60" aria-live="polite">
        {{ paused ? "Paused" : updatedAgo ? `Updated ${updatedAgo}` : "Live" }}
      </span>
    </template>
  </div>
</template>
