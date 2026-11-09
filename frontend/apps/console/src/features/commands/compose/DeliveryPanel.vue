<script setup lang="ts">
import { computed } from "vue";
import { formatCountdown, useNow, ApEmptyState, ApPanel, ApStatusMark } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * C4 · Delivery plan: each target's own next booked contact (M7 next_aos_at). Release fires at
 * that contact; targets without one get a caution row. Umbra margin omitted (DECISIONS #4).
 */
const props = defineProps<{ targets: readonly FleetSpacecraft[] }>();
const now = useNow();
const LIMIT = 40;
const rows = computed(() =>
  [...props.targets]
    .sort(
      (a, b) =>
        (a.next_aos_at ? Date.parse(a.next_aos_at) : Infinity) -
        (b.next_aos_at ? Date.parse(b.next_aos_at) : Infinity),
    )
    .slice(0, LIMIT),
);
const noContact = computed(() => props.targets.filter((sc) => sc.next_aos_at === null).length);
</script>

<template>
  <ApPanel index="C4" title="Delivery plan" meta="each target at its own next AOS" flush>
    <ApEmptyState v-if="targets.length === 0" headline="No targets yet" />
    <ul v-else class="m-0 list-none p-0">
      <li
        v-for="sc in rows"
        :key="sc.id"
        class="flex items-center gap-3 border-t border-hairline-faint px-4 py-1.5 first:border-t-0"
      >
        <ApStatusMark :state="sc.next_aos_at ? 'live' : 'caution'" />
        <span class="w-32 font-mono text-md text-readout">{{ sc.name }}</span>
        <span
          class="font-mono text-sm"
          :class="sc.next_aos_at ? 'text-text-2' : 'text-caution-text'"
        >
          {{
            sc.next_aos_at
              ? `AOS ${formatCountdown(new Date(sc.next_aos_at), now)}`
              : "No booked contact"
          }}
        </span>
      </li>
      <li
        v-if="targets.length > LIMIT"
        class="border-t border-hairline-faint px-4 py-1.5 font-mono text-xs text-text-4 uppercase"
      >
        and {{ targets.length - LIMIT }} more
      </li>
    </ul>
    <p v-if="noContact" class="m-0 border-t border-hairline px-4 py-2 text-md text-caution-text">
      {{ noContact }} without a booked contact:
      {{ noContact === 1 ? "its uplink waits" : "their uplinks wait" }} until one is booked.
      <RouterLink :to="{ name: 'ops.contacts' }" class="text-readout">Open contacts</RouterLink>
    </p>
  </ApPanel>
</template>
