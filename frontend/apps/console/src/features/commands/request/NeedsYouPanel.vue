<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout, ApListRow, ApPanel } from "@/ui";
import { needsYouCards } from "../groups/needsYou.ts";
import type { VerifierSeries } from "../groups/series.ts";
import type { Group } from "../groups/show.ts";

/**
 * N · Needs you (CommandFlow C3): one card per target a human has to look at, with what happened
 * in a sentence. No automatic retry (DECISIONS #69): `Re-send` opens Compose cloned from this group,
 * narrowed to those targets, through the normal GO. A released request with nothing to do says so.
 */
const props = defineProps<{ group: Group; series: VerifierSeries | null }>();
const cards = computed(() => needsYouCards(props.group, props.series));
const resendable = computed(() => cards.value.filter((c) => c.resend));
const resend = (ids: readonly string[]) => ({
  name: "ops.commands.new",
  query: { from: `group:${props.group.id}`, only: ids.join(",") },
});
</script>

<template>
  <ApPanel
    v-if="cards.length"
    index="N"
    title="Needs you"
    :meta="`${cards.length} ${cards.length === 1 ? 'target' : 'targets'}`"
    flush
  >
    <template v-if="resendable.length > 1" #meta>
      <ApButton
        size="compact"
        variant="secondary"
        :to="resend(resendable.map((c) => c.target.spacecraft_id))"
        >Re-send to all {{ resendable.length }}</ApButton
      >
    </template>
    <ul class="m-0 list-none p-0">
      <ApListRow
        v-for="c in cards"
        :key="c.target.spacecraft_id"
        :state="c.state"
        :title="c.target.name ?? 'Unknown spacecraft'"
        :meta="c.tag"
        :sentence="c.explanation"
      >
        <template #action>
          <span class="flex gap-1">
            <ApButton
              v-if="c.resend"
              size="compact"
              variant="secondary"
              :to="resend([c.target.spacecraft_id])"
              >Re-send</ApButton
            >
            <ApButton
              v-if="c.target.scid !== null"
              size="compact"
              variant="ghost"
              :to="{
                name: 'ops.spacecraft',
                params: { scId: String(c.target.scid), tab: 'investigate' },
              }"
              >Open</ApButton
            >
          </span>
        </template>
      </ApListRow>
    </ul>
  </ApPanel>
  <ApCallout v-else-if="group.state === 'queued'" tone="nominal">Nothing needs you.</ApCallout>
</template>
