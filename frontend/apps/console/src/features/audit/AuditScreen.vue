<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { canAdministerOrganization, useConsoleScope, useSession } from "@/shell";
import { ApPageHeader, ApRemote, ApSegmented } from "@/ui";
import AuditFilters from "./AuditFilters.vue";
import AuditResults from "./AuditResults.vue";
import AuditUnavailable from "./AuditUnavailable.vue";
import { auditKinds, kindText } from "./api.ts";
import { useAuditActor } from "./useAuditActor.ts";
import { useAuditExport } from "./useAuditExport.ts";
import { useAuditLog } from "./useAuditLog.ts";

/** Organization › Audit log. Says which sources are missing until the read is unified (ux spec). */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
/** Org admins only: a member never fires the read (qa: a 403 trips the e2e diagnostics guard). */
const session = useSession();
const isAdmin = computed(() =>
  organization.value ? canAdministerOrganization(session, organization.value) : false,
);
const days = ref<"1" | "7" | "30">("7");
const kind = ref<string>("all");
/** ApSegmented emits strings; keep only values this screen knows (typed v-model, lead c41e549d). */
const setDays = (v: string) => {
  if (v === "1" || v === "7" || v === "30") days.value = v;
};
const setKind = (v: string) => {
  kind.value = kindOptions.value.some((o) => o.value === v) ? v : "all";
};
const missionId = ref("");
/** One actor (Actor select, or People › person › Activity's link), in the query. */
const actor = useAuditActor(
  computed(() => (isAdmin.value ? (organization.value?.id ?? null) : null)),
);
const query = computed(() =>
  organization.value && isAdmin.value
    ? {
        organizationId: organization.value.id,
        days: Number(days.value),
        kinds: kind.value === "all" ? [] : [kind.value],
        missionId: missionId.value || null,
        ...(actor.id.value ? { actorId: actor.id.value } : {}),
        to: new Date(Math.floor(Date.now() / 60_000) * 60_000).toISOString(),
      }
    : null,
);
const log = useAuditLog(query);
const exporter = useAuditExport(
  query,
  computed(() => organization.value?.slug ?? "organization"),
);
const notProvided = computed(
  () => log.state.value.status === "failed" && log.state.value.error.kind === "not_found",
);
const span = computed(() => (days.value === "1" ? "24 hours" : `${days.value} days`));
const rangeOptions = [
  { value: "1", label: "24h" },
  { value: "7", label: "7d" },
  { value: "30", label: "30d" },
];
/** Sources the server reports beyond the known six get their own chip (ux); remembered once seen. */
const extraKinds = ref<readonly string[]>([]);
watch(log.state, (s) => {
  if (s.status !== "ready") return;
  const known = new Set<string>([...auditKinds, ...extraKinds.value]);
  const added = s.value.meta.sources.included.filter((k) => !known.has(k));
  if (added.length > 0) extraKinds.value = [...extraKinds.value, ...added];
});
const kindOptions = computed(() => [
  { value: "all", label: "All" },
  ...[...auditKinds, ...extraKinds.value].map((k) => ({ value: k, label: kindText(k) })),
]);
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
        v-if="isAdmin"
        :model-value="days"
        @update:model-value="setDays"
        label="Range"
        :options="rangeOptions"
      />
    </ApPageHeader>
    <AuditFilters
      v-if="isAdmin"
      v-model:mission-id="missionId"
      :kind="kind"
      :kind-options="kindOptions"
      :mission-options="missionOptions"
      :actor="actor"
      :exporter="exporter"
      @kind="setKind"
    />
    <AuditUnavailable v-if="!isAdmin || notProvided" :member="!isAdmin" />
    <ApRemote
      forbidden-text="Org admins see this."
      v-else
      :state="log.state.value"
      loading-label="Loading audit log…"
      @retry="log.refetch"
    >
      <template #default="{ value }">
        <AuditResults
          :events="value.items"
          :sources="value.meta.sources"
          :unshown="value.metas.flatMap((meta) => meta.unshown)"
          :has-more="value.next !== null"
          :loading="log.moreBusy.value"
          :failed="log.moreError.value !== null"
          :span="span"
          @older="log.more"
        />
      </template>
    </ApRemote>
  </div>
</template>
