<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useFleetPosture } from "@/shell";
import { postureChips, postureFromCounts } from "@/features/fleet/index.ts";
import { ApStatusMark, stateTextClass } from "@/ui";

/**
 * The cockpit cluster (ux): fleet health chips, the same as the top bar's posture
 * (posture.ts): crit and caution link to Alarms, stale to Fleet, and ground limits off to Apps.
 * The takeover header draws UTC itself (qa: it showed twice inside ClockCluster). The numbers are
 * the shell's /counts posture, which the top bar reads too: no fleet read per open dashboard
 * (#847; it used to read every row only to count them). Nothing until /counts has answered (U20).
 * `words` is the phone status bar's form (ux Dashboards.md §Phone): mark, count and word per chip
 * (`◆ 2 crit`), each a 48px link, and `■ Fleet nominal` when there's nothing to report. The
 * desktop header shows counts only and says nothing when nominal.
 */
const props = defineProps<{ words?: boolean | undefined }>();
const posture = useFleetPosture();
const chips = computed(() => {
  const p = posture.value;
  if (!p) return [];
  const all = postureChips(postureFromCounts(p));
  return props.words ? all : all.filter((chip) => chip.key !== "nominal");
});
</script>

<template>
  <span v-if="chips.length" class="flex items-center" :class="words ? 'gap-2' : 'gap-5'">
    <template v-for="(chip, i) in chips" :key="chip.key">
      <span v-if="words && i > 0" aria-hidden="true" class="text-text-4">·</span>
      <RouterLink
        :to="chip.to"
        class="flex items-center gap-1.5 tabular-nums no-underline hover:underline"
        :class="[stateTextClass(chip.state), words ? 'h-12' : '']"
        :aria-label="chip.label"
      >
        <ApStatusMark :state="chip.state" />
        <template v-if="chip.count === null">{{ chip.word }}</template>
        <template v-else
          >{{ chip.count }}<span v-if="words">{{ chip.word }}</span></template
        >
      </RouterLink>
    </template>
  </span>
</template>
