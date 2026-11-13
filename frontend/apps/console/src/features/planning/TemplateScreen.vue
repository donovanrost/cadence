<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, type ApCrumb } from "@/ui";
import TemplateEditor from "./TemplateEditor.vue";
import TemplateView from "./TemplateView.vue";
import { fetchPlanning, fetchTemplate } from "./api.ts";

/** Contact planning › one requirement template (CP3): read, edit (new version) or create. */
const route = useRoute("setup.contact-planning.template");
const scope = useMissionScope();
const templateId = computed(() =>
  typeof route.params.templateId === "string" ? route.params.templateId : null,
);
const isNew = computed(() => templateId.value === "new");
const { state, refetch } = useRemoteQuery(
  () =>
    templateId.value && !isNew.value
      ? { missionId: scope.value.mission.id, templateId: templateId.value }
      : null,
  fetchTemplate,
);
// Template writes and lifecycle moves share one check (:manage_mission); CP1 says it as planning.edit.
const planning = useRemoteQuery(() => scope.value.mission.id, fetchPlanning);
const canEdit = computed(
  () =>
    planning.state.value.status === "ready" &&
    planning.state.value.value.permissions.includes("planning.edit"),
);
const editing = ref(false);
function closed() {
  editing.value = false;
  refetch();
}
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Contact planning", to: { name: "setup.contact-planning" } },
  {
    label: isNew.value
      ? "New template"
      : state.value.status === "ready"
        ? state.value.value.name
        : "Template",
  },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader
      :title="isNew ? 'New template' : state.status === 'ready' ? state.value.name : 'Template'"
      size="reading"
    >
      <template v-if="!isNew && state.status === 'ready'" #subtitle
        ><span class="font-mono text-sm text-text-3">v{{ state.value.version }}</span></template
      >
      <ApButton
        v-if="
          canEdit &&
          !isNew &&
          !editing &&
          state.status === 'ready' &&
          state.value.state !== 'closed'
        "
        @click="editing = true"
        >Edit</ApButton
      >
    </ApPageHeader>
    <TemplateEditor
      v-if="isNew && canEdit"
      :mission-id="scope.mission.id"
      :template="null"
      @close="$router.push({ name: 'setup.contact-planning' })"
    />
    <ApRemote v-else-if="!isNew" :state="state" loading-label="Loading template…" @retry="refetch">
      <template #default="{ value }">
        <TemplateEditor
          v-if="editing"
          :mission-id="scope.mission.id"
          :template="value"
          @close="closed"
        />
        <TemplateView
          v-else
          :mission-id="scope.mission.id"
          :template="value"
          :can-edit="canEdit"
          @moved="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
