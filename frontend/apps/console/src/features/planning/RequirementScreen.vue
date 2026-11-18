<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, useInPlaceSwap, type ApCrumb } from "@/ui";
import RequirementEditor from "./RequirementEditor.vue";
import RequirementView from "./RequirementView.vue";
import { fetchRequirement, windowText } from "./requirements.ts";

/** Contact planning › one one-off requirement (ux ContactPlanning.md P4; api fb7510be). */
const route = useRoute("setup.contact-planning.requirement");
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const requirementId = computed(() =>
  typeof route.params.requirementId === "string" ? route.params.requirementId : null,
);
const isNew = computed(() => requirementId.value === "new");
const { state, refetch } = useRemoteQuery(
  () =>
    requirementId.value && !isNew.value
      ? { missionId: missionId.value, requirementId: requirementId.value }
      : null,
  fetchRequirement,
);
const session = useSession();
// Requirement writes need organization admin (api 8g, 403 otherwise).
const canEdit = computed(() => canAdministerOrganization(session, scope.value.organization));
// a11y A1/A5: Edit swaps the view for the editor (focus its first field); Save and Cancel swap back
// and return focus to Edit.
const root = ref<HTMLElement | null>(null);
const edit = useInPlaceSwap(root);
const editing = edit.open;
function closed() {
  refetch();
  void edit.hide();
}
const title = computed(() => {
  if (isNew.value) return "New requirement";
  const s = state.value;
  return s.status === "ready"
    ? `${s.value.spacecraft.name ?? "Unknown spacecraft"} · ${windowText(s.value.content)}`
    : "Requirement";
});
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Contact planning", to: { name: "setup.contact-planning" } },
  { label: isNew.value ? "New requirement" : "Requirement" },
]);
/** Any active requirement can be closed or canceled (ux: a template's occurrence too, alone). */
const endable = computed(
  () => canEdit.value && state.value.status === "ready" && state.value.value.state === "active",
);
/** Only a one-off is edited here; a template's occurrence changes in its template. */
const editable = computed(
  () => endable.value && state.value.status === "ready" && state.value.value.template_id === null,
);
</script>

<template>
  <div ref="root" class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="title" size="reading">
      <template v-if="!isNew && state.status === 'ready'" #subtitle
        ><span class="font-mono text-sm text-text-3">v{{ state.value.version }}</span></template
      >
      <ApButton v-if="editable && !editing" data-swap-opener @click="edit.show">Edit</ApButton>
    </ApPageHeader>
    <RequirementEditor
      v-if="isNew && canEdit"
      :mission-id="missionId"
      :requirement="null"
      @close="$router.push({ name: 'setup.contact-planning' })"
    />
    <ApRemote
      v-else-if="!isNew"
      :state="state"
      loading-label="Loading requirement…"
      @retry="refetch"
    >
      <template #default="{ value }">
        <!-- The swap marker sits on a wrapper: RequirementEditor's root is ApRemote's slot once loaded. -->
        <div v-if="editing" data-swap-editor class="contents">
          <RequirementEditor :mission-id="missionId" :requirement="value" @close="closed" />
        </div>
        <RequirementView
          v-else
          :mission-id="missionId"
          :requirement="value"
          :endable="endable"
          :can-edit="canEdit"
          @ended="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
