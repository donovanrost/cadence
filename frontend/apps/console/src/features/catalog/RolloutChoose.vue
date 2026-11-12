<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchProfiles } from "@/features/profiles/index.ts";
import { ApOption } from "@/ui";
import RolloutCanary from "./RolloutCanary.vue";
import RolloutProfiles from "./RolloutProfiles.vue";
import type { RolloutProfile } from "./rollout.ts";

/** C3's two option cards: by profile (listed first) or a few spacecraft first (a canary). */
const props = defineProps<{
  missionId: string;
  revisionNumber: number;
  profiles: readonly RolloutProfile[];
}>();
const mode = defineModel<"profiles" | "spacecraft" | null>("mode", { required: true });
const chosen = defineModel<readonly Readonly<{ id: string; allVersions: boolean }>[]>("chosen", {
  required: true,
});
const canary = defineModel<readonly string[]>("canary", { required: true });
const missionId = computed(() => props.missionId);
const list = useRemoteQuery(missionId, fetchProfiles);
const versions = computed(
  () =>
    new Map(
      list.state.value.status === "ready"
        ? list.state.value.value.map((p) => [p.id, p.version])
        : [],
    ),
);
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
    <legend class="ap-label mb-2">Roll out to</legend>
    <ApOption v-model="mode" value="profiles" name="rollout" title="By profile" />
    <RolloutProfiles
      v-if="mode === 'profiles'"
      v-model="chosen"
      :profiles="profiles"
      :versions="versions"
    />
    <ApOption
      v-model="mode"
      value="spacecraft"
      name="rollout"
      title="A few spacecraft first"
      :description="`Try rev ${revisionNumber} before moving a whole profile.`"
    />
    <RolloutCanary v-if="mode === 'spacecraft'" v-model="canary" :mission-id="missionId" />
  </fieldset>
</template>
