<script setup lang="ts">
import { UnshownCallout } from "@/features/now/index.ts";
import { computed } from "vue";
import { RouterLink, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatCountdown,
  formatDuration,
  useNow,
  ApButton,
  ApEmptyState,
  ApGantt,
  ApListRow,
  ApPanel,
  ApRemote,
  ApTag,
} from "@/ui";
import { fetchPasses, passGantt, type Pass } from "@/features/contacts/index.ts";
import { readinessTag } from "@/features/contacts/readiness.ts";
import { contactOpState, contactState, contactStateWord } from "@/features/scheduling/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { minutes } from "../history/api.ts";
import {
  byDay,
  bytesWords,
  causeWithOwner,
  fetchCoverage,
  fetchRecentPasses,
  rebooked,
  recentTag,
  ruleWords,
  type RecentPass,
  type SpacecraftCoverage,
} from "./api.ts";
import { SINGLE_BOOKINGS_LIVE } from "@/features/contacts/singleBookings.ts";

/** Tab · Passes (Investigate.md): when is it heard, and how did its recent passes go? */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
// A typed key (§12 A4), so the MissionId reaches the requests as one.
const key = computed(() => ({ m: missionId.value, sc: props.sc.id }));
const coverage = useRemoteQuery(key, (k, signal) => fetchCoverage(k.m, k.sc, signal));
const passes = useRemoteQuery(key, (k, signal) => {
  const t = Date.now();
  return fetchPasses(
    k.m,
    { from: new Date(t - 86_400_000), to: new Date(t + 86_400_000), spacecraftId: k.sc },
    signal,
  );
});
const recent = useRemoteQuery(key, (k, signal) => fetchRecentPasses(k.m, k.sc, signal));
useMissionInvalidation(missionId, ["contacts", "commanding", "pass_results"], () => {
  coverage.refetch();
  passes.refetch();
  recent.refetch();
});

const cov = computed(() =>
  coverage.state.value.status === "ready" ? coverage.state.value.value : null,
);
/** P1 next contact: coverage looks 7 days ahead (api ec39e09d). */
function nextContact(c: SpacecraftCoverage): string {
  const n = c.coverage.next_contact;
  return n
    ? `AOS ${formatCountdown(new Date(n.aos_at), now.value)} ${code(n.station)}`
    : "None booked";
}
/** P1 longest gap (ux review 3): with no pass at all the "gap" is the whole window. */
function gapWords(c: SpacecraftCoverage): string {
  if (c.coverage.passes_next_24h === 0) return "No pass in the next 24 h";
  const g = c.coverage.longest_gap;
  return g ? `${minutes(g.seconds)} from ${short(g.from)}` : "None";
}
const code = (s: { code: string | null; name: string | null } | null) => s?.code ?? s?.name ?? "—";
const t = (iso: string) => `${iso.slice(11, 16)}Z`;
const short = (iso: string) =>
  `${iso.slice(0, 10) === now.value.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${t(iso)}`;

const gantt = computed(() => {
  const s = passes.state.value;
  if (s.status !== "ready") return null;
  const window = { from: Date.parse(s.value.from), to: Date.parse(s.value.to) };
  return {
    window,
    ...passGantt(
      s.value.passes,
      () => ({ name: props.sc.name, scid: props.sc.scid }),
      now.value.getTime(),
      null,
      "spacecraft",
    ),
  };
});
const upcoming = computed<Pass[]>(() =>
  passes.state.value.status === "ready"
    ? passes.state.value.value.passes
        .filter((p) => Date.parse(p.ends_at) > now.value.getTime())
        .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
    : [],
);
const open = (id: string) =>
  router
    .push({ name: "ops.contacts", query: { contact: id } })
    .catch((e: unknown) => console.error("Navigation failed", e));
const link = (p: Pass) =>
  p.uplink_capable === null ? "" : p.uplink_capable ? "Up/down" : "Down only";
const notReady = (p: Pass) => {
  const r = p.uplink_readiness;
  return r && r.state !== "ready" ? readinessTag(r, "row") : null;
};
/** P4 line: flown window, cause and owner, received bytes only when known (ux review 4). */
const recentLine = (r: RecentPass) =>
  [
    r.actual_aos ? `Flown ${t(r.actual_aos)}–${r.actual_los ? t(r.actual_los) : "…"}` : "Not flown",
    causeWithOwner(r.cause, r.owner),
    r.received_bytes !== null ? `${bytesWords(r.received_bytes)} received` : null,
  ]
    .filter(Boolean)
    .join(" · ");
const days = computed(() =>
  recent.state.value.status === "ready" ? byDay(recent.state.value.value.rows) : [],
);
/** U86: passes this console couldn't read, for the line at the top of the list. */
const unshownPasses = computed(() =>
  passes.state.value.status === "ready" ? passes.state.value.value.unshown : [],
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3">
    <ApPanel index="P1" title="Coverage" flush class="flex-none">
      <template #meta>
        <RouterLink
          :to="{ name: 'ops.contacts', query: { view: 'spacecraft' } }"
          class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
          >Open in Contacts →</RouterLink
        >
      </template>
      <ApRemote
        :state="coverage.state.value"
        loading-label="LOADING COVERAGE…"
        @retry="coverage.refetch"
      >
        <dl
          v-if="cov"
          class="m-0 grid grid-cols-2 gap-x-6 gap-y-2 px-4 py-3 font-mono text-sm md:grid-cols-5"
        >
          <div>
            <dt class="ap-label">Last contact</dt>
            <dd class="m-0 text-readout">
              {{
                cov.coverage.last_contact
                  ? `LOS ${formatCountdown(new Date(cov.coverage.last_contact.los_at), now)} ${code(cov.coverage.last_contact.station)}`
                  : "None in 7 days"
              }}
            </dd>
          </div>
          <div>
            <dt class="ap-label">Next contact</dt>
            <dd
              class="m-0"
              :class="cov.coverage.next_contact ? 'text-readout' : 'text-caution-text'"
            >
              {{ nextContact(cov) }}
            </dd>
          </div>
          <div>
            <dt class="ap-label">Next 24 h</dt>
            <dd class="m-0 text-readout">
              {{ cov.coverage.passes_next_24h }}
              {{ cov.coverage.passes_next_24h === 1 ? "pass" : "passes" }}
            </dd>
          </div>
          <div>
            <dt class="ap-label">Longest gap</dt>
            <dd
              class="m-0"
              :class="cov.coverage.none_within_6h ? 'text-caution-text' : 'text-readout'"
            >
              {{ gapWords(cov) }}
              <!-- ux #9: only when a pass exists inside 24 h but none inside 6 h. -->
              <span
                v-if="cov.coverage.none_within_6h && cov.coverage.passes_next_24h > 0"
                class="block text-xs"
                >No pass in the next 6 h</span
              >
            </dd>
          </div>
          <div>
            <dt class="ap-label">Today</dt>
            <dd
              v-if="ruleWords(cov.coverage.contact_rule)"
              class="m-0"
              :class="
                ruleWords(cov.coverage.contact_rule)?.caution ? 'text-caution-text' : 'text-readout'
              "
            >
              {{ ruleWords(cov.coverage.contact_rule)?.text }}
            </dd>
            <dd v-else class="m-0 text-text-3">
              —
              <RouterLink :to="{ name: 'setup.contact-planning' }" class="text-text-2 underline"
                >no contact rule</RouterLink
              >
            </dd>
          </div>
        </dl>
      </ApRemote>
    </ApPanel>
    <!-- U86: above P2 and P3, so every width sees it (P2 is hidden on phones; lead). -->
    <UnshownCallout :unshown="unshownPasses" noun="pass" />
    <ApPanel index="P2" title="Passes · −24 h … +24 h" flush class="flex-none max-md:hidden">
      <div v-if="gantt" class="p-3">
        <ApGantt
          :label="`Passes for ${sc.name}, a day either side of now`"
          :rows="gantt.rows.length ? gantt.rows : [{ id: sc.id, label: sc.name }]"
          :bars="gantt.bars"
          :window="gantt.window"
          :now="now.getTime()"
          :lane-height="26"
          :label-width="Math.max(88, sc.name.length * 8 + 16)"
          @select="open"
        />
      </div>
    </ApPanel>
    <div
      class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]"
    >
      <ApPanel index="P3" title="Upcoming" pane flush>
        <ApRemote
          :state="passes.state.value"
          loading-label="LOADING PASSES…"
          @retry="passes.refetch"
        >
          <ApEmptyState
            v-if="upcoming.length === 0"
            state="off"
            :headline="`No passes booked for ${sc.name} in the next 24 h.`"
          >
            <!-- L15: the empty state links to Book a pass for this spacecraft (ux Contacts.md). -->
            <ApButton
              v-if="SINGLE_BOOKINGS_LIVE"
              size="compact"
              :to="{ name: 'ops.contacts', query: { book: sc.id } }"
              >Book a pass</ApButton
            >
            <ApButton v-else size="compact" :to="{ name: 'ops.contacts' }">Open Contacts</ApButton>
          </ApEmptyState>
          <ul v-else class="m-0 list-none p-0">
            <ApListRow
              v-for="p in upcoming"
              :key="p.id"
              :sentence="`${p.source.provider_name ?? 'Provider unknown'} · ${formatCountdown(new Date(p.starts_at), now)} · ${formatDuration((Date.parse(p.ends_at) - Date.parse(p.starts_at)) / 1000)}${link(p) ? ` · ${link(p)}` : ''}${cov?.queued[p.id] ? ` · ${cov.queued[p.id]} queued` : ''}`"
            >
              <template #title>
                <button
                  type="button"
                  class="max-md:hit-44 cursor-pointer font-mono text-readout hover:underline"
                  @click="open(p.id)"
                >
                  {{ code(p.station) }} · {{ short(p.starts_at) }}
                </button>
              </template>
              <template #action>
                <span class="flex flex-wrap justify-end gap-1">
                  <ApTag
                    :state="contactOpState(contactState(p))"
                    :label="contactStateWord[contactState(p)]"
                  />
                  <ApTag
                    v-if="notReady(p)"
                    :state="notReady(p)?.state"
                    :label="notReady(p)?.label ?? ''"
                  />
                </span>
              </template>
            </ApListRow>
          </ul>
        </ApRemote>
      </ApPanel>
      <ApPanel index="P4" title="Recent · 7 days" pane flush class="max-md:hidden">
        <ApRemote
          :state="recent.state.value"
          loading-label="LOADING RESULTS…"
          @retry="recent.refetch"
        >
          <ApEmptyState
            v-if="days.length === 0"
            state="off"
            headline="No passes in the last 7 days."
          />
          <section v-for="g in days" :key="g.day" :aria-label="g.day">
            <h3 class="ap-label m-0 border-b border-hairline px-4 pt-3 pb-1.5">
              <RouterLink
                :to="{ name: 'ops.contacts.review', query: { day: g.day } }"
                class="text-text-2 hover:text-readout"
                >{{ g.day }}</RouterLink
              >
            </h3>
            <ul class="m-0 list-none p-0">
              <ApListRow
                v-for="r in g.rows"
                :key="r.id"
                :state="recentTag(g.rows, r).state"
                :title="`${code(r.station)} · ${t(r.planned_aos)}–${t(r.planned_los)}${rebooked(g.rows, r) ? ' · re-booked' : ''}`"
                :sentence="recentLine(r)"
              >
                <template #action>
                  <ApTag :state="recentTag(g.rows, r).state" :label="recentTag(g.rows, r).label" />
                </template>
              </ApListRow>
            </ul>
          </section>
        </ApRemote>
      </ApPanel>
    </div>
  </div>
</template>
