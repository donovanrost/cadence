<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, stateTextClass } from "@/ui";
import type { PlanDetail } from "./api.ts";
import FocusChips from "./FocusChips.vue";
import { focusDay } from "./focus-day.ts";
import FocusStrip from "./FocusStrip.vue";
import type { SpacecraftName } from "./names.ts";

/**
 * K1 C · focused spacecraft · 24 h (ScheduleFlow C): rule chips, then its drafted passes on a
 * day strip with the gaps between them. Clicking a pass selects it for D. The gap and uplink chips
 * carry a verdict only when the server sends a limit or a need (both null until rules carry them,
 * BACKLOG §8 domain 7b); until then they're measures, never a HOLD.
 */
const props = defineProps<{
  plan: PlanDetail;
  day: string;
  focused: string | null;
  selected: string | null;
  nameOf: (id: string | null) => SpacecraftName | null;
  muted?: boolean | undefined;
}>();
defineEmits<{ select: [snapshotId: string] }>();

const window = computed(() => {
  const from = Date.parse(`${props.day}T00:00:00Z`);
  return { from, to: from + 86_400_000 };
});
const view = computed(() =>
  props.focused ? focusDay(props.plan, props.focused, window.value) : null,
);
const name = computed(() => {
  const sc = props.nameOf(props.focused);
  return sc ? sc.name : props.focused;
});
</script>

<template>
  <ApPanel
    index="C"
    :title="focused ? `${name} · 24 h` : 'Focused spacecraft · 24 h'"
    class="flex-none"
  >
    <template v-if="view && view.ruleMet !== null" #meta>
      <span :class="stateTextClass(view.ruleMet ? 'nominal' : 'caution')">{{
        view.ruleMet ? "Rule met" : "Rule not met"
      }}</span>
    </template>
    <p v-if="!view" class="m-0 text-md text-text-3">
      Pick a spacecraft in Demand to see its passes that day and the gaps between them.
    </p>
    <div v-else class="flex flex-col gap-3">
      <FocusChips :view="view" />
      <p v-if="view.passes.length === 0" class="m-0 text-md text-text-3">
        No passes drafted for {{ name }} on this day.
      </p>
      <div v-else class="flex flex-col gap-1" :class="muted ? 'opacity-60' : ''">
        <FocusStrip
          :view="view"
          :name="name ?? ''"
          :selected="selected"
          @select="$emit('select', $event)"
        />
      </div>
    </div>
  </ApPanel>
</template>
