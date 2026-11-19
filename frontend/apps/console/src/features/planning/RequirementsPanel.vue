<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApEmptyState, ApPanel, ApRemote, ApSegmented } from "@/ui";
import type { TemplateRow } from "./api.ts";
import { fetchRequirements } from "./requirements.ts";
import RequirementsPager from "./RequirementsPager.vue";
import RequirementsTable from "./RequirementsTable.vue";
import TemplateLinks from "./TemplateLinks.vue";

/**
 * P4 Requirements (ux ContactPlanning.md; api fb7510be): one-off by default. Templates can make
 * thousands a day, so "From templates" lists the templates, never their rows one by one.
 */
const props = defineProps<{
  missionId: MissionId;
  templates: readonly TemplateRow[];
  canEdit: boolean;
}>();
const filter = ref<"one_off" | "template" | "all">("one_off");
const filters = [
  { value: "one_off", label: "One-off" },
  { value: "template", label: "From templates" },
  { value: "all", label: "All" },
];
const setFilter = (v: string) => {
  if (v === "one_off" || v === "template" || v === "all") filter.value = v;
};
const page = ref(1);
watch(filter, () => (page.value = 1));
const query = computed(() =>
  filter.value === "template"
    ? null
    : {
        missionId: props.missionId,
        source: filter.value === "one_off" ? ("one_off" as const) : null,
        page: page.value,
      },
);
const list = useRemoteQuery(query, fetchRequirements);
// a11y A5: Newer/Older sit outside ApRemote, so the focused one stays while the next page loads;
// they keep the last page's next_page and wait (Loading…) until the new one arrives.
const nextPage = ref<number | null>(null);
watch(
  () => list.state.value,
  (s) => {
    if (s.status === "ready") nextPage.value = s.value.next_page;
  },
  { immediate: true },
);
const loading = computed(() => list.state.value.status === "loading");
</script>

<template>
  <ApPanel index="P4" title="Requirements" flush>
    <template v-if="canEdit" #header>
      <ApButton
        size="compact"
        variant="primary"
        :to="{ name: 'setup.contact-planning.requirement', params: { requirementId: 'new' } }"
        >New requirement</ApButton
      >
    </template>
    <div class="border-b border-hairline px-4 py-3">
      <ApSegmented
        :model-value="filter"
        :options="filters"
        label="Show"
        @update:model-value="setFilter"
      />
    </div>
    <TemplateLinks v-if="filter === 'template'" :mission-id="missionId" />
    <ApRemote
      v-else
      :state="list.state.value"
      loading-label="Loading requirements…"
      @retry="list.refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.requirements.length === 0"
          headline="No requirements"
          :sentence="
            filter === 'one_off'
              ? 'A one-off requirement is one spacecraft\'s need in one window.'
              : undefined
          "
        />
        <RequirementsTable v-else :rows="value.requirements" :templates="templates" />
      </template>
    </ApRemote>
    <RequirementsPager
      v-if="filter !== 'template' && (page > 1 || nextPage !== null)"
      :page="page"
      :next-page="nextPage"
      :busy="loading"
      @go="page = $event"
    />
  </ApPanel>
</template>
