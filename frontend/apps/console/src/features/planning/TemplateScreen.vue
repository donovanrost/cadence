<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import {
  ApBreadcrumb,
  ApKeyValue,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  formatAbsolute,
  plural,
  type ApColumn,
} from "@/ui";
import TemplateEditor from "./TemplateEditor.vue";
import { fetchTemplate, ruleText, type TemplateDetail } from "./api.ts";

/** Contact planning › one requirement template (CP3): read, edit (new version) or create. */
const route = useRoute();
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
const session = useSession();
// Template writes need organization admin (api CP3).
const canEdit = computed(() => canAdministerOrganization(session, scope.value.organization));
const editing = ref(false);
function closed() {
  editing.value = false;
  refetch();
}
const crumbs = computed(() => [
  { label: "Contact planning", to: { name: "setup.contact-planning" } },
  {
    label: isNew.value
      ? "New template"
      : state.value.status === "ready"
        ? state.value.value.name
        : "Template",
  },
]);
const facts = (t: TemplateDetail) => [
  { key: "rule", label: "Rule", value: ruleText(t.rule_summary), mono: true },
  {
    key: "applies",
    label: "Applies to",
    value: `${t.applies_to} · ${plural(t.applies_to_count, "spacecraft", "spacecraft")} now`,
  },
  { key: "priority", label: "Priority", value: t.priority.replaceAll("_", " ") },
  { key: "state", label: "State", value: t.state.replaceAll("_", " ") },
];
const columns: readonly ApColumn[] = [
  { key: "version", label: "Version", mono: true },
  { key: "at", label: "Created", mono: true },
  { key: "by", label: "By" },
];
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
        v-if="canEdit && !isNew && !editing && state.status === 'ready'"
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
        <template v-else>
          <ApPanel index="T1" title="Rule"
            ><ApKeyValue :items="facts(value)" :columns="2"
          /></ApPanel>
          <ApPanel
            index="T2"
            title="History"
            :meta="plural(value.versions.length, 'version')"
            flush
          >
            <ApTable
              :columns="columns"
              :rows="value.versions"
              :row-key="(v) => String(v.version)"
              caption="Template versions"
            >
              <template #cell-version="{ row }">v{{ row.version }}</template>
              <template #cell-at="{ row }">{{ formatAbsolute(new Date(row.created_at)) }}</template>
              <template #cell-by="{ row }">{{ row.actor?.name ?? "Not recorded" }}</template>
            </ApTable>
          </ApPanel>
          <p v-if="!canEdit" class="m-0 text-sm text-text-3">Org admins change contact planning.</p>
        </template>
      </template>
    </ApRemote>
  </div>
</template>
