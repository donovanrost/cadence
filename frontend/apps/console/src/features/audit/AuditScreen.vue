<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useConsoleScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented } from "@/ui";
import AuditFilters from "./AuditFilters.vue";
import AuditResults from "./AuditResults.vue";
import { auditKinds, kindLabel, type AuditKind } from "./api.ts";
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
/** ApSegmented emits strings; keep only values this screen knows (typed v-model, lead c41e549d). */
const setDays = (v: string) => {
  if (v === "1" || v === "7" || v === "30") days.value = v;
};
const setKind = (v: string) => {
  kind.value = v === "all" ? "all" : (auditKinds.find((k) => k === v) ?? "all");
};
const missionId = ref("");
/** `?actor=<user_id>&who=<name>`: one person's events (People › person › Activity links here). */
const route = useRoute();
const actorId = computed(() =>
  typeof route.query["actor"] === "string" ? route.query["actor"] : null,
);
const actorName = computed(() =>
  typeof route.query["who"] === "string" ? route.query["who"] : actorId.value,
);
const query = computed(() =>
  organization.value
    ? {
        organizationId: organization.value.id,
        days: Number(days.value),
        kinds: kind.value === "all" ? [] : [kind.value],
        missionId: missionId.value || null,
        ...(actorId.value ? { actorId: actorId.value } : {}),
        to: new Date(Math.floor(Date.now() / 60_000) * 60_000).toISOString(),
      }
    : null,
);
const log = useAuditLog(query);
const notProvided = computed(
  () => log.state.value.status === "failed" && log.state.value.error.kind === "not_found",
);
const span = computed(() => (days.value === "1" ? "24 hours" : `${days.value} days`));
const rangeOptions = [
  { value: "1", label: "24h" },
  { value: "7", label: "7d" },
  { value: "30", label: "30d" },
];
const kindOptions = [
  { value: "all", label: "All" },
  ...auditKinds.map((k) => ({ value: k, label: kindLabel[k] })),
];
const missionOptions = computed(() => [
  { value: "", label: "All missions" },
  ...(organization.value?.missions ?? []).map((m) => ({ value: m.id, label: m.name })),
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · audit log`"
      :title="`Last ${span}`"
      size="reading"
    >
      <ApSegmented
        :model-value="days"
        @update:model-value="setDays"
        label="Range"
        :options="rangeOptions"
      />
    </ApPageHeader>
    <AuditFilters
      v-model:mission-id="missionId"
      :kind="kind"
      :kind-options="kindOptions"
      :mission-options="missionOptions"
      :actor-name="actorId ? actorName : null"
      @kind="setKind"
    />
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
        <AuditResults
          :page="value"
          :older="log.older.value"
          :has-more="log.cursor.value !== null"
          :loading="log.loading.value"
          :failed="log.failed.value"
          :span="span"
          @older="log.loadOlder"
        />
      </template>
    </ApRemote>
  </div>
</template>
