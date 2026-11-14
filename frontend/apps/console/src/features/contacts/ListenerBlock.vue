<script setup lang="ts">
import { computed } from "vue";
import { ApCallout } from "@/ui";
import {
  listenerEvidence,
  listenerMeta,
  listenerTechnical,
  listenerTitle,
  type Attention,
} from "@/features/now/index.ts";

/**
 * U50 pass block (listener_refusal): connections a listener this pass shares were refused. Same
 * sentences as Now, with the title minus the spacecraft and pass label. Nothing to act on; the
 * address, keys and the count's liveness live in Technical details. Caution in both states: not
 * connected ranks P1, but nothing is known to be lost (ux, U20).
 */
const props = defineProps<{ attention: Attention; spacecraft: string | null; now: Date }>();
const title = computed(() =>
  listenerTitle(
    { ...props.attention, station: null, reservation_id: null, contact_label: null },
    null,
    props.now,
  ),
);
</script>

<template>
  <ApCallout tone="caution">
    <p class="m-0 font-semibold">{{ title }}</p>
    <p class="m-0 text-text-2">{{ listenerEvidence(attention, spacecraft, now) }}</p>
    <p class="m-0 font-mono text-xs text-text-3">{{ listenerMeta(attention, now) }}</p>
    <!-- ux U50: the address, the reason key and the profile live here only. -->
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p
        v-for="line in listenerTechnical(attention)"
        :key="line"
        class="m-0 pt-1 font-mono break-all"
      >
        {{ line }}
      </p>
    </details>
  </ApCallout>
</template>
