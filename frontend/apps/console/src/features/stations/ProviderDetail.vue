<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { ApButton, ApCallout, ApEmptyState, ApKeyValue, OutcomeCallout } from "@/ui";
import type { MissionProvider } from "./api.ts";
import EphemerisCounts from "./EphemerisCounts.vue";
import { ephemerisSummary } from "./ephemeris.ts";
import { membersQuery } from "./ephemerisMembers.ts";
import EphemerisMembers from "./EphemerisMembers.vue";
import ProviderArchive from "./ProviderArchive.vue";
import {
  checkProvider,
  checkSentence,
  grantLine,
  healthLine,
  providerFailure,
  revokedSentence,
} from "./providers.ts";

/** One provider (L12): what it's bound to, its health, and Validate / Sync stations / Archive. */
const props = defineProps<{
  missionId: MissionId;
  provider: MissionProvider | null;
  canManage: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();
// #972: Now's provider_ephemeris row opens the provider on its cause (and reason).
const route = useRoute();
const members = computed(() => membersQuery(route.query));
const busy = ref<"validate" | "sync" | null>(null);
const note = ref<{ tone: "nominal" | "info" | "caution" | "crit"; text: string } | null>(null);
const confirm = ref<InstanceType<typeof ProviderArchive> | null>(null);

async function check(what: "validate" | "sync") {
  if (!props.provider || busy.value) return;
  busy.value = what;
  note.value = { tone: "info", text: "Contacting the provider…" };
  try {
    const r = await checkProvider(props.missionId, props.provider.id, what);
    note.value = r.ok
      ? { tone: r.value.result.ok ? "nominal" : "caution", text: checkSentence(what, r.value) }
      : { tone: "crit", text: providerFailure(r.error) };
    if (r.ok) emit("changed");
  } finally {
    busy.value = null;
  }
}
function archived(n: { tone: "nominal" | "crit"; text: string }) {
  note.value = n;
  if (n.tone === "nominal") emit("changed");
}
const facts = (p: MissionProvider) => [
  {
    key: "account",
    label: "Account",
    value: p.account ? (p.account.name ?? "Org admins only") : "None: set up before account grants",
  },
  { key: "type", label: "Type", value: p.provider_type, mono: true },
  { key: "stations", label: "Stations", value: String(p.station_count) },
  { key: "validate", label: "Validated", value: healthLine(p.health.validate).text },
  { key: "sync", label: "Synced", value: healthLine(p.health.sync).text },
  { key: "grant", label: "Account grant", value: grantLine(p.grant).text },
  { key: "orbits", label: "Orbits", value: ephemerisSummary(p.ephemeris).lead },
];
</script>

<template>
  <ApEmptyState
    v-if="!provider"
    state="off"
    headline="No such provider"
    sentence="It may have been archived."
  />
  <div v-else class="flex flex-col gap-3 p-4">
    <h2 class="m-0 text-lg text-readout">{{ provider.name }}</h2>
    <ApKeyValue :items="facts(provider)" :columns="2">
      <template #value-grant>
        <span :class="grantLine(provider.grant).revoked ? 'text-crit-text' : ''">{{
          grantLine(provider.grant).text
        }}</span>
      </template>
      <template #value-orbits
        ><EphemerisCounts :ephemeris="provider.ephemeris" :provider-id="provider.id"
      /></template>
    </ApKeyValue>
    <ApCallout v-if="provider.grant?.state === 'revoked'" tone="crit">{{
      revokedSentence(provider.account?.name ?? null)
    }}</ApCallout>
    <OutcomeCallout v-if="note" :outcome="note" />
    <div
      v-if="canManage && provider.status.lifecycle_state === 'active'"
      class="flex flex-wrap gap-2"
    >
      <ApButton :disabled="busy !== null" disabled-reason="Working…" @click="check('validate')"
        >Validate</ApButton
      >
      <ApButton :disabled="busy !== null" disabled-reason="Working…" @click="check('sync')"
        >Sync stations</ApButton
      >
      <ApButton
        variant="danger"
        :disabled="busy !== null"
        disabled-reason="Working…"
        @click="confirm?.open()"
        >Archive…</ApButton
      >
    </div>
    <EphemerisMembers
      v-if="members"
      :mission-id="missionId"
      :provider-id="provider.id"
      :cause="members.cause"
      :reason="members.reason"
    />
    <ProviderArchive
      ref="confirm"
      :mission-id="missionId"
      :provider-id="provider.id"
      @done="archived"
    />
  </div>
</template>
