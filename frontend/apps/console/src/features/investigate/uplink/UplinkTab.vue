<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatCountdown,
  formatDuration,
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApListRow,
  ApPanel,
  ApRemote,
  ApTag,
} from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import { STAGE_STATE, STAGE_WORDS } from "@/features/commands/groups/words.ts";
import type { MemberStage } from "@/features/commands/groups/api.ts";
import {
  groupBlockedLine,
  noRecoverText,
  readinessTag,
  recoverable,
} from "@/features/contacts/readiness.ts";
import RecoverUplink from "@/features/contacts/RecoverUplink.vue";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import {
  argsSummary,
  evidenceWords,
  fetchSpacecraftUplink,
  releaseRule,
  routeMeta,
  shortAt,
  type SpacecraftUplink,
} from "./api.ts";

/** Tab · Uplink (Investigate.md): can I command this spacecraft now, and what's going up? */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
const now = useNow();
const access = useCommandAccess();
const missionId = computed(() => scope.value.mission.id);
const uplink = useRemoteQuery(
  computed(() => ({ m: missionId.value, sc: props.sc.id })),
  (k, signal) => fetchSpacecraftUplink(k.m, k.sc, signal),
);
useMissionInvalidation(missionId, ["commanding", "contacts", "attention"], uplink.refetch);

const code = (s: { code: string | null; name: string | null }) => s.code ?? s.name ?? "—";
const tagOf = (r: Parameters<typeof readinessTag>[0] | null) =>
  r ? readinessTag(r, "drawer") : null;
/** U4: delivery and verification in C3's words (member stage vocabulary). */
const stageTag = (state: MemberStage | "unrecognized" | null) =>
  state !== null && state !== "unrecognized"
    ? { label: STAGE_WORDS[state], state: STAGE_STATE[state] }
    : { label: "Sent", state: "neutral" as const };
/** U3: when the pass the lane waits for is blocked, the U33 group line. */
const blockedLine = (u: SpacecraftUplink) =>
  u.waits_for
    ? groupBlockedLine(
        { pass: u.waits_for.pass, readiness: u.waits_for.readiness, next_pass: undefined },
        null,
      )
    : null;
/** ux #12: U2 says "other" only when U1's pass is itself inside the 24 h it counts. */
const nowWithin24h = (u: SpacecraftUplink) =>
  u.now !== null && Date.parse(u.now.pass.starts_at) - now.value.getTime() <= 86_400_000;
const composeTo = computed((): RouteLocationRaw => ({
  name: "ops.commands.new",
  query: { targets: `sc:${props.sc.id}` },
}));
</script>

<template>
  <ApRemote :state="uplink.state.value" loading-label="LOADING UPLINK…" @retry="uplink.refetch">
    <template #default="{ value: u }">
      <div class="flex min-h-0 flex-1 flex-col gap-3">
        <ApPanel index="U1" title="Now" :meta="routeMeta(u)" flush class="flex-none">
          <ApCallout v-if="!u.now" tone="caution">
            No pass with uplink is booked for {{ sc.name }}.
            <template #action
              ><ApButton size="compact" :to="{ name: 'ops.contacts' }"
                >Open Contacts</ApButton
              ></template
            >
          </ApCallout>
          <div v-else class="flex flex-wrap items-center gap-3 px-4 py-3">
            <span class="font-mono text-md text-readout uppercase">
              <template v-if="u.now.in_contact"
                >In contact · {{ code(u.now.pass.station) }} · LOS
                {{ formatCountdown(new Date(u.now.pass.ends_at), now) }}</template
              >
              <template v-else
                >Next commandable pass · {{ code(u.now.pass.station) }}
                {{ shortAt(u.now.pass.starts_at, now) }} ·
                {{ formatCountdown(new Date(u.now.pass.starts_at), now) }}</template
              >
            </span>
            <template v-if="tagOf(u.now.readiness)">
              <ApTag
                :state="tagOf(u.now.readiness)?.state"
                :label="tagOf(u.now.readiness)?.label ?? ''"
              />
              <span v-if="tagOf(u.now.readiness)?.sentence" class="text-sm text-text-2">{{
                tagOf(u.now.readiness)?.sentence
              }}</span>
            </template>
            <template v-if="u.now.readiness?.state === 'blocked'">
              <RecoverUplink
                v-if="recoverable(u.now.readiness.reason)"
                :mission-id="missionId"
                :pass-id="u.now.pass.reservation_id"
                :recovering="false"
                :can-recover="access.abort"
                @changed="uplink.refetch"
              />
              <span v-else-if="noRecoverText(u.now.readiness.reason)" class="text-sm text-text-2">{{
                noRecoverText(u.now.readiness.reason)
              }}</span>
            </template>
            <span aria-hidden="true" class="flex-1" />
            <ApButton v-if="access.request" class="max-md:hidden" variant="primary" :to="composeTo"
              >Command {{ sc.name }}</ApButton
            >
          </div>
        </ApPanel>
        <div
          class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[360px_minmax(0,1fr)]"
        >
          <ApPanel index="U2" title="Next commandable passes" flush class="max-md:hidden">
            <ul class="m-0 list-none p-0">
              <ApListRow
                v-for="p in u.next_passes"
                :key="p.reservation_id"
                :title="`${code(p.station)} · ${shortAt(p.starts_at, now)}`"
                :sentence="`${p.provider?.name ?? 'Provider unknown'} · ${formatCountdown(new Date(p.starts_at), now)} · ${formatDuration((Date.parse(p.ends_at) - Date.parse(p.starts_at)) / 1000)}`"
                :meta="evidenceWords(p).text"
                :state="evidenceWords(p).caution ? 'caution' : undefined"
              />
            </ul>
            <p
              v-if="u.next_passes.length < 3"
              class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3"
            >
              {{
                u.next_passes.length === 0
                  ? `No ${nowWithin24h(u) ? "other " : ""}commandable pass is booked in the next 24 h.`
                  : `Only ${u.next_passes.length} commandable ${u.next_passes.length === 1 ? "pass is" : "passes are"} booked in the next 24 h.`
              }}
            </p>
          </ApPanel>
          <ApPanel index="U3" title="Queued on its lane" pane flush>
            <ApEmptyState
              v-if="u.queue.length === 0"
              state="off"
              :headline="`Nothing is queued for ${sc.name}.`"
            />
            <template v-else>
              <p
                v-if="blockedLine(u)"
                class="m-0 border-b border-hairline px-4 py-2 text-sm text-crit-text"
              >
                {{ blockedLine(u) }}
              </p>
              <ul class="m-0 list-none p-0">
                <ApListRow
                  v-for="q in u.queue"
                  :key="q.request_id"
                  :sentence="`${releaseRule(q, now)}${u.waits_for ? ` · waits for ${code(u.waits_for.pass.station)} ${shortAt(u.waits_for.pass.starts_at, now)}` : ''}`"
                >
                  <template #title>
                    <span class="font-mono text-xs text-text-4">{{
                      String(q.position).padStart(2, "0")
                    }}</span>
                    <span class="ml-2 font-mono font-semibold text-readout">{{
                      q.command_name ?? q.command_id
                    }}</span>
                    <span class="ml-2 font-mono text-sm text-text-3">{{
                      argsSummary(q.arguments_json)
                    }}</span>
                    <RouterLink
                      v-if="q.group"
                      :to="{ name: 'ops.commands.request', params: { requestId: q.group.id } }"
                      class="max-md:hit-44 ml-2 text-sm text-text-2 hover:text-readout"
                      >{{ q.group.title }}</RouterLink
                    >
                  </template>
                </ApListRow>
              </ul>
            </template>
          </ApPanel>
        </div>
        <ApPanel
          index="U4"
          title="Released · last 24 h"
          pane
          flush
          class="max-md:hidden console:max-h-[34%]"
        >
          <ApEmptyState
            v-if="u.released.length === 0"
            state="off"
            :headline="`Nothing was released to ${sc.name} in the last 24 h.`"
          />
          <ul v-else class="m-0 list-none p-0">
            <ApListRow
              v-for="r in u.released"
              :key="r.request_id"
              :state="stageTag(r.verification_state).state"
              :sentence="shortAt(r.released_at, now)"
            >
              <template #title>
                <span class="font-mono font-semibold text-readout">{{
                  r.command_name ?? "Command"
                }}</span>
                <RouterLink
                  v-if="r.group"
                  :to="{ name: 'ops.commands.request', params: { requestId: r.group.id } }"
                  class="max-md:hit-44 ml-2 text-sm text-text-2 hover:text-readout"
                  >{{ r.group.title }}</RouterLink
                >
              </template>
              <template #action>
                <ApTag
                  :state="stageTag(r.verification_state).state"
                  :label="stageTag(r.verification_state).label"
                />
              </template>
            </ApListRow>
          </ul>
        </ApPanel>
      </div>
    </template>
  </ApRemote>
</template>
