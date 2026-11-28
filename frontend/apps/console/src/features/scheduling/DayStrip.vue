<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { useNow } from "@/ui";
import { fetchPlanDays, stripCell, stripDays, type MarkState } from "./day-strip.ts";

/**
 * K1's day strip (DECISIONS #100; ScheduleFlow §K1 day strip): the next 7 UTC days, today first,
 * each a link to `?day=` with its plan's state in U61's words. Marks are decoration only.
 */
const props = defineProps<{ day: string }>();
const route = useRoute();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const now = useNow();
const days = computed(() => stripDays(now.value));
const read = useRemoteQuery(
  computed(() => ({ m: missionId.value, from: days.value[0] ?? "", to: days.value[6] ?? "" })),
  (k, signal) => fetchPlanDays(k.m, k.from, k.to, signal),
);
useMissionInvalidation(missionId, ["contacts", "contact_plans"], read.refetch);
const cells = computed(() =>
  read.state.value.status === "ready"
    ? read.state.value.value.days.map((d) => stripCell(d, now.value))
    : [],
);
const MARK: Readonly<Record<MarkState, string>> = {
  nominal: "text-nominal",
  caution: "text-caution-text",
  crit: "text-crit-text",
};
</script>

<template>
  <nav v-if="cells.length > 0" aria-label="Next 7 days" class="min-w-0 overflow-x-auto">
    <ul class="m-0 flex list-none gap-1 p-0">
      <li v-for="c in cells" :key="c.day">
        <RouterLink
          :to="{ query: { ...route.query, day: c.day, run: undefined, version: undefined } }"
          :aria-label="c.name"
          :aria-current="c.day === props.day ? 'date' : undefined"
          class="flex min-w-[112px] flex-col gap-0.5 border border-hairline px-3 py-1.5 text-text no-underline hover:bg-raised"
          :class="c.day === props.day ? 'bg-raised shadow-[inset_0_-2px_0_var(--color-text)]' : ''"
        >
          <span class="font-mono text-xs text-text-2 uppercase">{{ c.label }}</span>
          <!-- #1027: a real space, so the shown text reads "Mon 30 No plan" as the name does, never
               "Mon 30No plan" (WCAG 2.5.3); the template drops plain whitespace between spans. -->
          {{ " " }}
          <span class="flex items-center gap-1 text-sm"
            ><span v-if="c.mark" aria-hidden="true" :class="MARK[c.mark.state]">{{
              c.mark.glyph
            }}</span
            >{{ c.word }}</span
          >
        </RouterLink>
      </li>
    </ul>
  </nav>
</template>
