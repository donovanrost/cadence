<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, ApTag, stateTextClass } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { focusDay } from "./focus-day.ts";
import FocusStrip from "./FocusStrip.vue";
import type { SpacecraftName } from "./names.ts";

/**
 * K1 C · focused spacecraft · 24 h (ScheduleFlow C): rule chips, then its drafted passes on a
 * day strip with the gaps between them. Clicking a pass selects it for D. Only the contacts chip
 * carries a verdict: the server sends no gap limit or uplink count yet (BACKLOG §8 domain 7), so
 * the longest gap is a measure, never a HOLD.
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
const contactsMet = computed(() => {
  const c = view.value?.contacts;
  return c && c.need !== null ? c.have >= c.need : null;
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
      Pick a spacecraft in Demand to see its day: passes, and the gaps between them.
    </p>
    <div v-else class="flex flex-col gap-3">
      <ul class="m-0 flex list-none flex-wrap items-center gap-x-4 gap-y-2 p-0">
        <li v-if="view.contacts" class="flex items-center gap-2 font-mono text-sm text-text-2">
          Contacts {{ view.contacts.have
          }}{{ view.contacts.need === null ? "" : `/${view.contacts.need}` }}
          <ApTag
            v-if="contactsMet !== null"
            :state="contactsMet ? 'nominal' : 'caution'"
            :label="contactsMet ? 'GO' : 'HOLD'"
          />
        </li>
        <li v-if="view.longestGapSeconds !== null" class="font-mono text-sm text-text-2">
          Longest gap {{ view.gaps.find((g) => g.longest)?.text }}
        </li>
      </ul>
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
