<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { useRemoteQuery } from "@/api";
import {
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApStatusMark,
  ApTable,
  formatShort,
  useNow,
  type ApColumn,
} from "@/ui";
import { fetchServiceIdentities, keyAgeWarning } from "./api.ts";

/** U3 Service identities (org admins). Last use isn't tracked yet, so that column is left out. */
const props = defineProps<{ organizationId: OrganizationId }>();
const { state, refetch } = useRemoteQuery(() => props.organizationId, fetchServiceIdentities);
const now = useNow();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Identity", mono: true },
  { key: "scope", label: "Scope" },
  { key: "key", label: "Key created", mono: true },
];
</script>

<template>
  <ApPanel index="U3" title="Service identities" flush>
    <template #meta>
      <RouterLink :to="{ name: 'org.people.services.new' }" class="text-text-3 hover:text-readout"
        >New</RouterLink
      >
    </template>
    <ApRemote
      forbidden-text="Org admins see this."
      :state="state"
      loading-label="Loading service identities…"
      @retry="refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.service_identities.length === 0"
          headline="No service identities"
          sentence="Pipelines and integrations authenticate as service identities."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="value.service_identities"
          :row-key="(s) => s.id"
          caption="Service identities"
        >
          <template #cell-name="{ row }"
            ><RouterLink
              :to="{ name: 'org.people.service', params: { serviceId: row.id } }"
              class="font-semibold text-readout hover:underline"
              >{{ row.name }}</RouterLink
            ></template
          >
          <template #cell-scope="{ row }">{{ row.scope_summary }}</template>
          <template #cell-key="{ row }">
            <span>{{ row.key_created_at ? formatShort(new Date(row.key_created_at)) : "—" }}</span>
            <span
              v-if="keyAgeWarning(row.key_created_at, value.rotation_policy_days, now)"
              class="flex items-center gap-2 font-sans text-sm text-caution-text"
              ><ApStatusMark state="caution" />{{
                keyAgeWarning(row.key_created_at, value.rotation_policy_days, now)
              }}</span
            >
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
