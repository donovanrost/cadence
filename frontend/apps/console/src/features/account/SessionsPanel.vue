<script setup lang="ts">
import { ref } from "vue";
import { useRemoteQuery } from "@/api";
import {
  ApButton,
  ApCallout,
  type ApColumn,
  ApPanel,
  ApRemote,
  ApTable,
  ApTag,
  formatShort,
  outcomeRole,
  plural,
} from "@/ui";
import { fetchSessions, signOutOthers, signOutSession } from "./api.ts";

/** People.md Account · sessions. No device or address is recorded, so rows say when they began. */
const { state, refetch } = useRemoteQuery(() => true as const, fetchSessions);
const busy = ref(false);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const columns: readonly ApColumn[] = [
  { key: "started", label: "Session" },
  { key: "expires", label: "Expires", mono: true },
  { key: "action", label: "Action", hiddenLabel: true, align: "end" },
];
defineExpose({ refetch });
const when = (iso: string) => formatShort(new Date(iso));
const unclear =
  "No clear answer from the server, so it may or may not have signed out. The list has been reloaded.";

async function run(work: () => Promise<{ ok: boolean; text: string }>) {
  busy.value = true;
  try {
    const r = await work();
    note.value = { tone: r.ok ? "nominal" : "caution", text: r.text };
    refetch();
  } finally {
    busy.value = false;
  }
}
const one = (id: string) =>
  run(async () => {
    const r = await signOutSession(id);
    return r.ok ? { ok: true, text: "Signed that session out." } : { ok: false, text: unclear };
  });
const others = () =>
  run(async () => {
    const r = await signOutOthers();
    return r.ok
      ? { ok: true, text: `Signed out ${plural(r.value.revoked, "other session")}.` }
      : { ok: false, text: unclear };
  });
</script>

<template>
  <ApPanel index="A4" title="Sessions" flush>
    <ApRemote :state="state" loading-label="Loading sessions…" @retry="refetch">
      <template #default="{ value }">
        <ApTable
          :columns="columns"
          :rows="value.sessions"
          :row-key="(s) => s.id"
          caption="Your sessions"
        >
          <template #cell-started="{ row }">
            <span class="flex items-center gap-2">
              Signed in <span class="font-mono">{{ when(row.started_at) }}</span>
              <ApTag v-if="row.current" state="off" label="This session" />
            </span>
          </template>
          <template #cell-expires="{ row }">{{ when(row.expires_at) }}</template>
          <template #cell-action="{ row }">
            <ApButton
              v-if="!row.current"
              size="compact"
              variant="ghost"
              :disabled="busy"
              disabled-reason="Working…"
              @click="one(row.id)"
              >Sign out</ApButton
            >
          </template>
        </ApTable>
        <div class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-3">
          <ApButton
            v-if="value.sessions.some((s) => !s.current)"
            :disabled="busy"
            disabled-reason="Working…"
            @click="others"
            >Sign out other sessions</ApButton
          >
          <span v-else class="text-sm text-text-3">Only this session is signed in.</span>
          <ApCallout v-if="note" :tone="note.tone" :role="outcomeRole(note.tone)">{{
            note.text
          }}</ApCallout>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
