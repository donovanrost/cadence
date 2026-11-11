<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApListRow, ApPanel } from "@/ui";
import type { Group } from "../groups/show.ts";
import { memberStageWord, NEEDS_YOU, STAGE_STATE } from "../groups/words.ts";

/**
 * N · Needs you (CommandFlow C3): targets whose uplink failed or is unclear. No automatic retry
 * (DECISIONS #69): `Re-send` opens Compose cloned from this group, narrowed to those targets,
 * through the normal GO. Hidden when nothing needs a human.
 */
const props = defineProps<{ group: Group }>();
const failed = computed(() => props.group.targets.filter((t) => NEEDS_YOU.includes(t.stage)));
const resend = (ids: readonly string[]) => ({
  name: "ops.commands.new",
  query: { from: `group:${props.group.id}`, only: ids.join(",") },
});
</script>

<template>
  <ApPanel
    v-if="failed.length"
    index="N"
    title="Needs you"
    :meta="`${failed.length} ${failed.length === 1 ? 'target' : 'targets'}`"
    flush
  >
    <template v-if="failed.length > 1" #meta>
      <ApButton size="compact" variant="secondary" :to="resend(failed.map((t) => t.spacecraft_id))"
        >Re-send to all {{ failed.length }}</ApButton
      >
    </template>
    <ul class="m-0 list-none p-0">
      <ApListRow
        v-for="t in failed"
        :key="t.spacecraft_id"
        :state="STAGE_STATE[t.stage]"
        :title="t.name ?? 'Unknown spacecraft'"
        :sentence="memberStageWord(t.stage, group.state)"
      >
        <template #action>
          <span class="flex gap-1">
            <ApButton size="compact" variant="secondary" :to="resend([t.spacecraft_id])"
              >Re-send</ApButton
            >
            <ApButton
              v-if="t.scid !== null"
              size="compact"
              variant="ghost"
              :to="{ name: 'ops.spacecraft', params: { scId: String(t.scid), tab: 'investigate' } }"
              >Open</ApButton
            >
          </span>
        </template>
      </ApListRow>
    </ul>
  </ApPanel>
</template>
