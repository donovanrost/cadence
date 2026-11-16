<script setup lang="ts">
import { computed, ref } from "vue";
import { isKnown, useRemoteQuery, type SessionOrganization } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, ApSelect } from "@/ui";
import { fetchCommandPolicies, policyText } from "./policies.ts";

/** U4 · Command policies (read-only, DECISIONS #7): each as a title + one sentence, per mission. */
const props = defineProps<{ organization: SessionOrganization }>();
const missionId = ref<string>(props.organization.missions[0]?.id ?? "");
/** The select's text back to the session's MissionId (§12C). */
const mission = computed(
  () => props.organization.missions.find((m) => m.id === missionId.value)?.id ?? null,
);
const options = computed(() =>
  props.organization.missions.map((m) => ({ value: m.id, label: m.name })),
);
const { state, refetch } = useRemoteQuery(
  () => mission.value,
  (id, signal) => fetchCommandPolicies(id, signal),
);
</script>

<template>
  <ApPanel index="U4" title="Command policies">
    <template v-if="options.length > 1" #header
      ><div class="w-[220px]">
        <ApSelect v-model="missionId" label="Mission" hidden-label :options="options" /></div
    ></template>
    <ApEmptyState v-if="!missionId" state="off" headline="No missions yet" />
    <ApRemote v-else :state="state" loading-label="Loading policies…" @retry="refetch">
      <template #default="{ value }">
        <ul class="m-0 flex list-none flex-col gap-3 p-0">
          <li
            v-for="p in value.policies"
            :key="isKnown(p.key) ? p.key : p.key.unrecognized"
            class="flex flex-col gap-0.5"
          >
            <span class="font-semibold text-readout">{{ policyText(p).title }}</span>
            <span class="text-md text-text-2">{{ policyText(p).sentence }}</span>
          </li>
        </ul>
        <p class="m-0 mt-4 text-sm text-text-3">Policies become configurable per mission later.</p>
      </template>
    </ApRemote>
  </ApPanel>
</template>
