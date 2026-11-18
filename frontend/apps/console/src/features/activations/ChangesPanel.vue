<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { UnshownCallout } from "@/features/now/index.ts";
import { ApCallout, ApPanel, plural } from "@/ui";
import ChangeGroupBlock from "./ChangeGroupBlock.vue";
import {
  changesHeading,
  isFleet,
  orderedGroups,
  summaryLines,
  telemetryOffLine,
  unseenCraft,
  unshownRows,
} from "./changesWords.ts";
import type { ConfigurationChanges } from "./configurationChanges.ts";
import type { DetailKey } from "./api.ts";

/**
 * #235 (ux U94): what a spacecraft-configuration request changes, so the approver approves the
 * change itself. A fleet gets the summary from the groups' counts, then each group.
 */
const props = defineProps<{
  changes: ConfigurationChanges;
  requestKey: DetailKey;
  index: string;
}>();
const fleet = computed(() => isFleet(props.changes));
const offLine = computed(() => telemetryOffLine(props.changes));
/** ux #235: an unreadable group is named by its craft, "what changes for 12 spacecraft". */
const unseenWhat = computed(() => {
  const n = unseenCraft(props.changes);
  return n > 0 ? `what changes for ${plural(n, "spacecraft", "spacecraft")}` : undefined;
});
/** One craft: its page, where the Operation panel turns telemetry on; a fleet: the craft list. */
const operation = computed(() => {
  const only = props.changes.groups.items[0]?.spacecraft[0];
  return !fleet.value && only
    ? { name: "setup.spacecraft.one" as const, params: { spacecraftId: only.spacecraft_id } }
    : { name: "setup.spacecraft" as const };
});
</script>

<template>
  <ApPanel :index="index" :title="changesHeading(changes)">
    <div class="flex max-w-[760px] flex-col gap-3">
      <UnshownCallout :unshown="unshownRows(changes)" noun="change" />
      <UnshownCallout :unshown="changes.groups.unshown" :what="unseenWhat" />
      <ul v-if="fleet" class="m-0 flex list-none flex-col gap-1 p-0 text-md text-text-2">
        <li v-for="line in summaryLines(changes)" :key="line">{{ line }}</li>
      </ul>
      <ApCallout v-if="offLine" :tone="offLine.tone">
        {{ offLine.text }}
        <template #action
          ><RouterLink :to="operation" class="text-sm text-readout underline hover:text-bright"
            >Open Operation</RouterLink
          ></template
        >
      </ApCallout>
      <ChangeGroupBlock
        v-for="g in orderedGroups(changes)"
        :key="g.index"
        :group="g"
        :request-key="requestKey"
        :fleet="fleet"
      />
    </div>
  </ApPanel>
</template>
