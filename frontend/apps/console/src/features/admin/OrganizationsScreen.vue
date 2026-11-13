<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import {
  ApButton,
  ApCallout,
  ApField,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  formatShort,
  plural,
  type ApColumn,
} from "@/ui";
import { fetchOrganizations } from "./api.ts";
import OrganizationCreate from "./OrganizationCreate.vue";
import PlatformCaption from "./PlatformCaption.vue";

/** Admin › Organizations (Admin.md): filter, table, Create organization. */
const q = ref("");
const list = useRemoteQuery(() => ({ q: q.value.trim(), after: null }), fetchOrganizations);
const create = ref<InstanceType<typeof OrganizationCreate> | null>(null);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const title = computed(() =>
  list.state.value.status === "ready"
    ? plural(list.state.value.value.organizations.length, "organization")
    : "Organizations",
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "slug", label: "Slug", mono: true },
  { key: "members", label: "Members", mono: true, align: "end" },
  { key: "missions", label: "Missions", mono: true, align: "end" },
  { key: "created", label: "Created" },
];
function created(text: { tone: "nominal" | "caution"; text: string }) {
  note.value = text;
  list.refetch();
}
</script>

<template>
  <ApPageHeader label="Platform admin · organizations" :title="title" size="reading">
    <ApButton variant="primary" @click="create?.open()">Create organization</ApButton>
  </ApPageHeader>
  <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
  <ApField v-model="q" label="Filter" hidden-label placeholder="Filter by name or slug" />
  <ApPanel index="O1" title="Organizations" flush>
    <ApRemote
      :state="list.state.value"
      loading-label="Loading organizations…"
      @retry="list.refetch"
    >
      <template #default="{ value }">
        <ApTable
          :columns="columns"
          :rows="value.organizations"
          :row-key="(o) => o.id"
          caption="Organizations"
        >
          <template #cell-name="{ row }">
            <RouterLink
              :to="{ name: 'admin.organization', params: { orgId: row.id } }"
              class="font-semibold text-readout hover:underline"
              >{{ row.name }}</RouterLink
            >
          </template>
          <template #cell-created="{ row }">
            <span class="text-text-2"
              >{{ row.created_by?.name ?? "Not recorded"
              }}<template v-if="row.created_at">
                · {{ formatShort(new Date(row.created_at)) }}</template
              ></span
            >
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
  <OrganizationCreate ref="create" @created="created" />
  <PlatformCaption />
</template>
