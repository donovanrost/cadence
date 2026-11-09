<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, formatCountdown, useNow } from "@/ui";
import type { PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";
import { unconfirmedView, type UnconfirmedPass } from "./unconfirmed.ts";

/**
 * U30 caution block, shared by K1 and K2 (exported): who hasn't confirmed what, and the passes
 * soonest first with T− to the first. U32's per-pass actions (fe-setup's features/resolutions,
 * DECISIONS #53) come in through the `row-actions` slot; screens fill it only for org admins.
 */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  /** Non-admins, once resolution exists: say who can act (U32). */
  memberNote?: boolean | undefined;
}>();
defineSlots<{ "row-actions"?: (props: { pass: UnconfirmedPass }) => unknown }>();
const now = useNow();
const view = computed(() =>
  unconfirmedView(props.plan, props.nameOf, now.value.toISOString().slice(0, 10)),
);
</script>

<template>
  <ApCallout v-if="view" tone="caution">
    <span class="flex flex-col gap-1">
      <span>{{ view.headline }}</span>
      <span
        v-for="(pass, i) in view.passes"
        :key="pass.snapshot_id"
        class="flex flex-wrap items-center gap-x-3 gap-y-1"
      >
        <span class="font-mono text-sm text-text-2 tabular"
          >{{ pass.text
          }}<template v-if="i === 0"> · {{ formatCountdown(pass.startsAt, now) }}</template></span
        >
        <slot name="row-actions" :pass="pass" />
      </span>
      <span v-if="memberNote" class="text-sm text-text-3"
        >Org admins resolve unconfirmed bookings.</span
      >
    </span>
  </ApCallout>
</template>
