<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, formatShort } from "@/ui";
import { changeLines, fetchAccountVersions } from "./history.ts";

/** V3 · History: settings and credential-reference versions (renames make no version). */
const props = defineProps<{ orgId: OrganizationId; accountId: string }>();
const key = computed(() => ({ orgId: props.orgId, id: props.accountId }));
const { state, refetch } = useRemoteQuery(key, fetchAccountVersions);
defineExpose({ refetch });
const who = (a: { name: string | null } | null) => (a?.name ? ` · by ${a.name}` : "");
</script>

<template>
  <ApPanel index="V3" title="History" flush>
    <!-- ux: renames make no version; provider account changes are in the audit log (api a52b6fbe). -->
    <p class="m-0 px-4 pt-2.5 text-sm text-text-3">
      Renames aren't versioned, so they don't appear here; the
      <RouterLink :to="{ name: 'org.audit' }" class="text-readout underline">Audit log</RouterLink>
      has them.
    </p>
    <ApRemote :state="state" loading-label="Loading history…" @retry="refetch">
      <template #default="{ value }">
        <ApEmptyState v-if="value.versions.length === 0" state="off" headline="No versions yet" />
        <ol v-else class="m-0 list-none p-0">
          <li
            v-for="(v, i) in value.versions"
            :key="v.version"
            class="flex flex-col gap-1 border-t border-hairline-faint px-4 py-2.5 first:border-t-0"
          >
            <span class="font-mono text-sm text-text-2"
              >v{{ v.version
              }}<template v-if="v.version === value.current_version"> · current</template> ·
              {{ formatShort(new Date(v.created_at)) }}{{ who(v.actor) }}</span
            >
            <span
              v-for="line in changeLines(v, i === value.versions.length - 1)"
              :key="line"
              class="text-md text-text-2"
              >{{ line }}</span
            >
          </li>
        </ol>
      </template>
    </ApRemote>
  </ApPanel>
</template>
