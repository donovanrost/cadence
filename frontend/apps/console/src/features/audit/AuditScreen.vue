<script setup lang="ts">
import { computed, ref } from "vue";
import { useConsoleScope } from "@/shell";
import {
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApSelect,
  formatCount,
} from "@/ui";
import AuditTable from "./AuditTable.vue";
import { auditKinds, kindLabel, listWords, type AuditKind, type AuditPage } from "./api.ts";
import { useAuditLog } from "./useAuditLog.ts";

/** Organization › Audit log. Says which sources are missing until the read is unified (ux spec). */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const days = ref<"1" | "7" | "30">("7");
const kind = ref<AuditKind | "all">("all");
const missionId = ref("");
const query = computed(() =>
  organization.value
    ? {
        organizationId: organization.value.id,
        days: Number(days.value),
        kinds: kind.value === "all" ? [] : [kind.value],
        missionId: missionId.value || null,
        to: new Date(Math.floor(Date.now() / 60_000) * 60_000).toISOString(),
      }
    : null,
);
const log = useAuditLog(query);
const notProvided = computed(
  () => log.state.value.status === "failed" && log.state.value.error.kind === "not_found",
);
const span = computed(() => (days.value === "1" ? "24 hours" : `${days.value} days`));
const kindOptions = [
  { value: "all", label: "All" },
  ...auditKinds.map((k) => ({ value: k, label: kindLabel[k] })),
];
const missionOptions = computed(() => [
  { value: "", label: "All missions" },
  ...(organization.value?.missions ?? []).map((m) => ({ value: m.id, label: m.name })),
]);
const words = (p: AuditPage, which: "included" | "missing") =>
  listWords(p.sources[which].map((k) => kindLabel[k].toLowerCase()));
const capitalized = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · audit log`"
      :title="`Last ${span}`"
      size="reading"
    >
      <ApSegmented
        v-model="days"
        label="Range"
        :options="[
          { value: '1', label: '24h' },
          { value: '7', label: '7d' },
          { value: '30', label: '30d' },
        ]"
      />
    </ApPageHeader>
    <div class="flex flex-wrap items-end gap-3">
      <ApSegmented v-model="kind" label="Kind" :options="kindOptions" />
      <ApSelect v-model="missionId" label="Mission" :options="missionOptions" />
    </div>
    <ApPanel v-if="notProvided" index="L1" title="Audit log" flush>
      <ApEmptyState
        state="off"
        headline="The audit log isn't available in the console yet"
        sentence="Configuration revisions are in Setup › Revisions in the meantime."
      />
    </ApPanel>
    <ApRemote
      v-else
      :state="log.state.value"
      loading-label="Loading audit log…"
      @retry="log.refetch"
    >
      <template #default="{ value }">
        <ApCallout v-if="value.sources.missing.length > 0" tone="info">
          Showing {{ words(value, "included") }} events.
          {{ capitalized(words(value, "missing")) }} events aren't in the audit log yet.
        </ApCallout>
        <ApPanel index="L1" title="Audit" flush>
          <ApEmptyState
            v-if="value.events.length === 0"
            :headline="`No audited actions in the last ${span}`"
          />
          <AuditTable v-else :events="[...value.events, ...log.older.value]">
            <template #footer>
              <div
                v-if="log.cursor.value || log.failed.value"
                class="flex items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
              >
                <span>{{ formatCount(value.events.length + log.older.value.length) }} shown</span>
                <ApButton
                  v-if="log.cursor.value"
                  size="compact"
                  :disabled="log.loading.value"
                  disabled-reason="Loading…"
                  @click="log.loadOlder"
                  >Load older</ApButton
                >
                <span v-if="log.failed.value" class="text-caution-text"
                  >Older events couldn't load.</span
                >
              </div>
            </template>
          </AuditTable>
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
