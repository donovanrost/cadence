<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { ApCallout, ApPanel, ApRemote } from "@/ui";
import type { DataSource } from "./api.ts";
import BindingHistorySheet from "./BindingHistorySheet.vue";
import BindingSwitchSheet from "./BindingSwitchSheet.vue";
import MissionBindingsTable from "./MissionBindingsTable.vue";
import { fetchMissionBindings, type MissionBinding } from "./bindings.ts";
import PlatformSwitchSheet from "./PlatformSwitchSheet.vue";
import { ADMIN_ONLY, PLATFORM_HIDDEN, visibleBindings } from "./platform.ts";
import { usePlatformSwitch } from "./usePlatformSwitch.ts";

/** D2 · the mission's bindings (own first, then the platform-wide ones it falls back to; U53). */
const props = defineProps<{
  missionId: MissionId;
  sources: readonly DataSource[];
  canManage: boolean;
}>();
const bindings = useRemoteQuery(() => props.missionId, fetchMissionBindings);
useMissionInvalidation(
  computed(() => props.missionId),
  ["data_sources"],
  bindings.refetch,
);
const showPlatform = ref(false);
const platformAdmin = usePlatformSwitch();
const note = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);
const own = ref<InstanceType<typeof BindingSwitchSheet> | null>(null);
const platform = ref<InstanceType<typeof PlatformSwitchSheet> | null>(null);
const history = ref<InstanceType<typeof BindingHistorySheet> | null>(null);
const rows = (all: readonly MissionBinding[]) => visibleBindings(all, showPlatform.value);
const sharedCount = (all: readonly MissionBinding[]) => all.filter((b) => b.shared).length;
const target = (b: MissionBinding) => ({
  id: b.id,
  logical_source: b.logical_source,
  data_source_id: b.data_source.id,
});
function openSwitch(b: MissionBinding) {
  note.value = null;
  if (b.shared) platform.value?.open(target(b));
  else own.value?.open(target(b));
}
function done(n: { tone: "nominal" | "crit"; text: string }) {
  note.value = n;
  bindings.refetch();
}
</script>

<template>
  <ApPanel index="D2" title="Bindings" flush>
    <ApRemote
      :state="bindings.state.value"
      loading-label="Loading bindings…"
      @retry="bindings.refetch"
    >
      <template #default="{ value }">
        <label
          class="flex items-center gap-2 border-b border-hairline px-4 py-2.5 text-md text-text-2"
        >
          <input
            v-model="showPlatform"
            type="checkbox"
            role="switch"
            class="size-4 accent-[var(--color-readout)]"
          />
          Show platform bindings ({{ sharedCount(value) }})
        </label>
        <p v-if="!showPlatform" class="m-0 px-4 py-2 text-sm text-text-3">{{ PLATFORM_HIDDEN }}</p>
        <MissionBindingsTable
          :rows="rows(value)"
          :can-manage="canManage"
          :platform-admin="platformAdmin"
          @switch="openSwitch"
          @history="history?.open($event)"
        />
        <p
          v-if="showPlatform && sharedCount(value) > 0 && !platformAdmin"
          class="m-0 px-4 py-2 text-sm text-text-3"
        >
          {{ ADMIN_ONLY }}
        </p>
      </template>
    </ApRemote>
    <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
  </ApPanel>
  <BindingSwitchSheet ref="own" :mission-id="missionId" :sources="sources" @done="done" />
  <PlatformSwitchSheet ref="platform" :mission-id="missionId" :sources="sources" @done="done" />
  <BindingHistorySheet ref="history" :mission-id="missionId" />
</template>
