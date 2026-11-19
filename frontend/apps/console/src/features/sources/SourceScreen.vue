<script setup lang="ts">
import { computed, onScopeDispose, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useAdminMode, useMissionScope } from "@/shell";
import { ApBreadcrumb, ApCallout, ApPageHeader, ApRemote, ApTag, type ApCrumb } from "@/ui";
import { fetchSources } from "./api.ts";
import { access, enabledTag, kindText, runsActive } from "./present.ts";
import SourceActions from "./SourceActions.vue";
import SourceBindings from "./SourceBindings.vue";
import SourceFacts from "./SourceFacts.vue";
import SourceRuns from "./SourceRuns.vue";
import { fetchSourceDetail } from "./writes.ts";

/** One data source (L11 R2): facts, actions, bindings, TSDB runs. Polls while a run is active. */
const props = defineProps<{ sourceId: string }>();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const detail = useRemoteQuery(
  () => ({ missionId: missionId.value, sourceId: props.sourceId }),
  fetchSourceDetail,
);
/** Every source, for a binding's switch choices. */
const sources = useRemoteQuery(missionId, fetchSources);
const list = computed(() =>
  sources.state.value.status === "ready" ? sources.state.value.value : null,
);
const adminMode = useAdminMode(() => new Date()).active;
const rights = (s: Parameters<typeof access>[0]) =>
  access(s, list.value?.canManage ?? false, adminMode.value);
useMissionInvalidation(missionId, ["data_sources"], () => {
  detail.refetch();
  sources.refetch();
});
const note = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);
watch(
  () => props.sourceId,
  () => (note.value = null),
);
// api-ops: poll R2 about every 5 s while a run is queued or running.
let timer: ReturnType<typeof setInterval> | null = null;
watch(
  () => runsActive(detail.state.value.status === "ready" ? detail.state.value.value : null),
  (active) => {
    if (timer) clearInterval(timer);
    timer = active ? setInterval(() => detail.refetch(), 5000) : null;
  },
  { immediate: true },
);
onScopeDispose(() => timer && clearInterval(timer));
function done(n: { tone: "nominal" | "crit"; text: string }) {
  note.value = n;
  detail.refetch();
}
const crumbs: readonly ApCrumb[] = [
  // An optional param isn't carried over by name, so this is the list.
  { label: "Data sources", to: { name: "setup.data-sources" } },
  { label: "Source" },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApRemote :state="detail.state.value" loading-label="Loading source…" @retry="detail.refetch">
      <template #default="{ value }">
        <ApPageHeader
          :label="`${scope.mission.name} · data source · ${kindText(value.source.kind)}`"
          :title="value.source.display_name"
          size="reading"
        >
          <ApTag
            v-if="enabledTag(value.source)"
            :state="enabledTag(value.source)?.state ?? 'off'"
            :label="enabledTag(value.source)?.label ?? ''"
          />
        </ApPageHeader>
        <ApCallout v-if="rights(value.source).line" tone="info">{{
          rights(value.source).line
        }}</ApCallout>
        <SourceActions v-else :mission-id="missionId" :source="value.source" @done="done" />
        <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
        <SourceFacts :source="value.source" />
        <!-- A binding is the mission's even when it reads from a shared source: mission operators
          switch it (the server checks the binding's owner, not the source's; qa L11). -->
        <SourceBindings
          :mission-id="missionId"
          :bindings="value.bindings"
          :sources="list?.sources ?? []"
          :editable="list?.canManage ?? false"
          @done="done"
        />
        <SourceRuns
          :mission-id="missionId"
          :runs="value.runs"
          :editable="rights(value.source).editable"
          @done="done"
        />
      </template>
    </ApRemote>
  </div>
</template>
