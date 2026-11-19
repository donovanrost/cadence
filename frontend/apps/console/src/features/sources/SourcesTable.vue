<script setup lang="ts">
import { ApStatusMark, ApTable, ApTag, type ApColumn } from "@/ui";
import type { DataSource } from "./api.ts";
import { enabledTag, freshness, health, kindText } from "./present.ts";

/** D1 rows: the name links to the source's page (L11); freshness and health as the server judges. */
defineProps<{ sources: readonly DataSource[] }>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Source" },
  { key: "kind", label: "Kind" },
  { key: "fresh", label: "Freshness" },
  { key: "health", label: "Health" },
  { key: "creds", label: "Credentials" },
];
const credsClass = (s: DataSource) =>
  s.credentials?.status === "expired"
    ? "text-crit-text"
    : s.credentials?.status === "expiring"
      ? "text-caution-text"
      : "text-text-3";
</script>

<template>
  <ApTable :columns="columns" :rows="sources" :row-key="(s) => s.id" caption="Data sources">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.data-sources', params: { sourceId: row.id } }"
        class="font-semibold text-primary no-underline hover:underline max-md:hit-44"
        >{{ row.display_name }}</RouterLink
      >
      <ApTag
        v-if="enabledTag(row)?.state === 'off'"
        class="ml-2"
        :state="enabledTag(row)?.state ?? 'off'"
        :label="enabledTag(row)?.label ?? ''"
      />
    </template>
    <template #cell-kind="{ row }"
      ><span class="text-text-2">{{ kindText(row.kind) }}</span
      ><span v-if="row.shared" class="text-text-3"> · shared</span></template
    >
    <template #cell-fresh="{ row }"
      ><span class="inline-flex items-center gap-2"
        ><ApStatusMark :state="freshness(row).state" />{{ freshness(row).text }}</span
      ></template
    >
    <template #cell-health="{ row }"
      ><span class="inline-flex items-center gap-2"
        ><ApStatusMark :state="health(row).state" />{{ health(row).text }}</span
      ></template
    >
    <template #cell-creds="{ row }">
      <span :class="credsClass(row)">{{ row.credentials?.status ?? "—" }}</span>
    </template>
  </ApTable>
</template>
