<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { ApButton, ApCallout, formatCountdown, refocusFirst, useNow } from "@/ui";
import type { PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";
import { unconfirmedView, type UnconfirmedPass } from "./unconfirmed.ts";
import UnconfirmedSheet from "./UnconfirmedSheet.vue";

/**
 * U30 caution block, shared by K1 and K2 (exported): who hasn't confirmed what, and the passes
 * soonest first with T− to the first. U32's per-pass actions (fe-setup's features/resolutions,
 * DECISIONS #53) come in through the `row-actions` slot; screens fill it only for org admins.
 * The 1 Hz T− is aria-hidden: the callout is role=status and would re-read it every second (a11y B4).
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
/** ux U30 cap: the soonest 5; every pass in a sheet, so the callout never pushes A/B/D out. */
const CAP = 5;
const sheet = ref<InstanceType<typeof UnconfirmedSheet> | null>(null);
const shown = computed(() => view.value?.passes.slice(0, CAP) ?? []);
const hidden = computed(() => (view.value ? view.value.passes.length - CAP : 0));
/**
 * #244 (A5): resolving a pass removes its row (and the actions that had focus). Once the list
 * changes, focus goes to the callout, or the page's heading when none is left, only if it was lost.
 */
const box = ref<HTMLElement | null>(null);
watch(
  () => view.value?.passes.length ?? 0,
  async () => {
    await nextTick();
    refocusFirst(box.value);
  },
);
</script>

<template>
  <div v-if="view" ref="box" tabindex="-1">
    <ApCallout tone="caution">
      <span class="flex flex-col gap-1">
        <span>{{ view.headline }}</span>
        <span
          v-for="(pass, i) in shown"
          :key="pass.snapshot_id"
          class="flex flex-wrap items-center gap-x-3 gap-y-1"
        >
          <span class="font-mono text-sm text-text-2 tabular"
            >{{ pass.text
            }}<span v-if="i === 0" aria-hidden="true">
              · {{ formatCountdown(pass.startsAt, now) }}</span
            ></span
          >
          <slot name="row-actions" :pass="pass" />
        </span>
        <span v-if="hidden > 0" class="flex items-center gap-2">
          <span class="text-sm text-text-3">and {{ hidden }} more ·</span>
          <ApButton variant="ghost" size="compact" @click="sheet?.open()"
            >Show all {{ view.passes.length }}</ApButton
          >
        </span>
        <span v-if="memberNote" class="text-sm text-text-3"
          >Org admins resolve unconfirmed bookings.</span
        >
      </span>
    </ApCallout>
  </div>
  <!-- #244 (A5): mounted while there's a view, not only while some are hidden, so resolving a pass
    from inside the open sheet (dropping the count to 5 or fewer) doesn't unmount it. -->
  <UnconfirmedSheet
    v-if="view"
    ref="sheet"
    :title="`${view.count} unconfirmed bookings`"
    :passes="view.passes"
  >
    <template v-if="$slots['row-actions']" #row-actions="{ pass }">
      <slot name="row-actions" :pass="pass" />
    </template>
  </UnconfirmedSheet>
</template>
