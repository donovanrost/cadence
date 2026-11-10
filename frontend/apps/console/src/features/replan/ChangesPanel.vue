<script setup lang="ts">
import { computed } from "vue";
import { ApListRow, ApPanel, ApStatStrip, ApStatTile, plural } from "@/ui";
import type { Pass } from "@/features/contacts/index.ts";
import {
  reasonText,
  type PlanDetail,
  type Repair,
  type SpacecraftName,
} from "@/features/scheduling/index.ts";
import CoveredList from "./CoveredList.vue";
import { moveLine, sameWindow } from "./moves.ts";

/** C · Changes (K2): what the repair keeps, moves, drops and adds, then what needs a person. */
const props = defineProps<{
  diff: NonNullable<Repair["diff"]>;
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  /** The passes read over the plan window: names the separate booking that covers a lost one. */
  bookings: readonly Pass[];
}>();
const name = (id: string | null) => props.nameOf(id)?.name ?? id ?? "Unknown spacecraft";
const sample = computed(() => props.diff.moved.slice(0, 8));
const rebooked = computed(() => props.diff.moved.filter(sameWindow).length);
</script>

<template>
  <ApPanel
    index="C"
    title="Changes"
    :meta="`${plural(diff.moved.length, 'pass', 'passes')} moved · ${diff.dropped.length} dropped`"
    pane
    flush
  >
    <div class="p-3">
      <!-- ux: Kept · Moved · Added · Covered · Dropped; 3 columns (two rows) fit the 360px pane. -->
      <ApStatStrip :columns="3" label="Repair changes">
        <ApStatTile label="Kept" :value="diff.kept.length" />
        <ApStatTile
          label="Moved"
          :value="diff.moved.length"
          :caption="rebooked > 0 ? `${rebooked} in the same window` : undefined"
        />
        <ApStatTile label="Added" :value="diff.added.length" />
        <ApStatTile
          label="Covered"
          :value="diff.covered.length"
          :caption="diff.covered.length > 0 ? 'already booked separately' : undefined"
        />
        <!-- Spans the row's last two cells, so no empty cell shows the strip's fill. -->
        <ApStatTile
          class="col-span-2"
          label="Dropped"
          :value="diff.dropped.length"
          :state="diff.dropped.length > 0 ? 'caution' : 'neutral'"
        />
      </ApStatStrip>
    </div>
    <h3 class="ap-label px-4 pt-2">Need you</h3>
    <ul v-if="plan.unmet.length > 0" class="m-0 list-none p-0">
      <ApListRow
        v-for="gap in plan.unmet"
        :key="gap.requirement_id"
        state="caution"
        :title="name(gap.spacecraft_id)"
        :sentence="gap.why.map(reasonText).join(' · ') || 'Rule not met after the re-plan'"
      />
    </ul>
    <p v-else class="m-0 px-4 py-2 text-md text-text-3">
      Every rule is still met after the re-plan.
    </p>
    <h3 v-if="sample.length > 0" class="ap-label px-4 pt-3">Moves</h3>
    <ul class="m-0 list-none p-0 font-mono text-sm">
      <li
        v-for="m in sample"
        :key="m.to.snapshot_id"
        class="flex flex-wrap gap-x-2 border-t border-hairline-faint px-4 py-1.5 first:border-t-0"
      >
        <span class="text-readout">{{ name(m.spacecraft_id) }}</span>
        <span class="text-text-3">{{ moveLine(m).route }}</span>
        <span v-if="moveLine(m).offset" class="text-text-4">{{ moveLine(m).offset }}</span>
      </li>
    </ul>
    <p
      v-if="diff.moved.length > sample.length"
      class="m-0 px-4 py-2 font-mono text-xs text-text-4 uppercase"
    >
      Showing {{ sample.length }} of {{ diff.moved.length }} moves
    </p>
    <CoveredList :covered="diff.covered" :bookings="bookings" :name="name" />
  </ApPanel>
</template>
