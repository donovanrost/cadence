<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
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
import { fetchTemplate, type TemplateDetail } from "./api.ts";

/** Contact planning › one requirement template (CP3): read-only until the template schema exists. */
const route = useRoute();
const scope = useMissionScope();
const templateId = computed(() =>
  typeof route.params.templateId === "string" ? route.params.templateId : null,
);
const { state, refetch } = useRemoteQuery(
  () =>
    templateId.value ? { missionId: scope.value.mission.id, templateId: templateId.value } : null,
  fetchTemplate,
);
const crumbs = computed(() => [
  { label: "Contact planning", to: { name: "setup.contact-planning" } },
  { label: state.value.status === "ready" ? state.value.value.name : "Template" },
]);
const facts = (t: TemplateDetail) => [
  { key: "rule", label: "Rule", value: t.rule_summary, mono: true },
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
    <ApPageHeader :title="state.status === 'ready' ? state.value.name : 'Template'" size="reading">
      <template v-if="state.status === 'ready'" #subtitle
        ><span class="font-mono text-sm text-text-3">v{{ state.value.version }}</span></template
      >
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading template…" @retry="refetch">
      <template #default="{ value }">
        <ApPanel index="T1" title="Rule"><ApKeyValue :items="facts(value)" :columns="2" /></ApPanel>
        <ApPanel index="T2" title="History" :meta="plural(value.versions.length, 'version')" flush>
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
        <p class="m-0 text-sm text-text-3">
          Editing templates arrives with the requirement field schema.
        </p>
      </template>
    </ApRemote>
  </div>
</template>
