<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { describeApiError, usePagedQuery, type PageFetcher } from "@/api/index.ts";
import { ApButton } from "@/ui";
import ContactRecordView from "./ContactRecordView.vue";
import { fetchReservation, type Reservation } from "./records.ts";
import { useShowEarlier } from "./pageFocus.ts";
import { clock, sentenceCase, TONE_CLASS, valueCells, withVersion } from "./recordWords.ts";
import { planRoute, requirementRoute, type PlanRef } from "./planLinks.ts";
import type { RouteLocationRaw } from "vue-router";

/**
 * The pass's reservation and contact records (ux U74, api A11/A13) as two collapsed Technical
 * details disclosures in mono key/values. Nothing is read until one is opened.
 */
const props = defineProps<{
  missionId: MissionId;
  passId: string;
  providerName: string | null;
  /** The pass's own plan (its day opens K1 on that day); null for a direct booking. */
  plan?: PlanRef | null;
}>();
const opened = ref(false);
type Key = Readonly<{ m: MissionId; pass: string }>;
type AuditEntry = Reservation["audit"]["entries"][number];
/** The reservation itself rides on each page; the provider audit is what pages (25 a page). */
const fetchPage: PageFetcher<Key, AuditEntry, Omit<Reservation, "audit">> = async (
  k,
  cursor,
  signal,
) => {
  const page = await fetchReservation(k.m, k.pass, cursor, signal);
  if (!page.ok) return page;
  const { audit, ...reservation } = page.value;
  return { ok: true, value: { items: audit.entries, next: audit.next_cursor, meta: reservation } };
};
const query = usePagedQuery(
  computed<Key | null>(() => (opened.value ? { m: props.missionId, pass: props.passId } : null)),
  fetchPage,
  (entry) => entry.id,
);
const r = computed(() =>
  query.state.value.status === "ready" ? query.state.value.value.meta : null,
);
/** The provider audit, every page loaded (Show earlier appends the next). */
const audit = computed(() =>
  query.state.value.status === "ready" ? query.state.value.value.items : [],
);
const hasEarlier = computed(
  () => query.state.value.status === "ready" && query.state.value.value.next !== null,
);
const listEl = ref<HTMLElement | null>(null);
const moreEl = ref<HTMLElement | null>(null);
const showEarlier = useShowEarlier(query, listEl, moreEl);
type Fact = Readonly<{ key: string; text: string; to: RouteLocationRaw | null }>;
/**
 * #676: the plan and the requirement open their screens (the plan on K1, on the pass's plan day
 * when it's the same plan); the other ids are Technical details text.
 */
const facts = computed<Fact[]>(() => {
  const v = r.value?.reservation;
  if (!v) return [];
  const id = (x: { id: string; version: number | null } | null) =>
    x ? withVersion(x.id, x.version) : null;
  const day = props.plan && v.plan && props.plan.id === v.plan.id ? props.plan.day : null;
  const rows: [string, string | null, RouteLocationRaw | null][] = [
    ["Reservation", v.id, null],
    ["Provider revision", v.provider_revision === null ? null : String(v.provider_revision), null],
    ["State", sentenceCase(v.lifecycle_state), null],
    ["Provider", withVersion(props.providerName ?? v.provider.id, v.provider.version), null],
    ["Transport", id(v.transport), null],
    ["Plan", id(v.plan), v.plan ? planRoute({ ...v.plan, day }) : null],
    ["Requirement", id(v.requirement), v.requirement ? requirementRoute(v.requirement.id) : null],
    ["Scheduled contact", v.scheduled_contact_id, null],
    ["Last reconciled", v.last_reconciled_at ? clock(v.last_reconciled_at) : null, null],
  ];
  return rows.flatMap(([key, text, to]) => (text === null ? [] : [{ key, text, to }]));
});
const onToggle = (e: Event) => {
  if (e.target instanceof HTMLDetailsElement && e.target.open) opened.value = true;
};
</script>

<template>
  <details class="text-xs text-text-3" @toggle="onToggle">
    <summary class="cursor-pointer font-mono uppercase">Reservation</summary>
    <p v-if="query.state.value.status === 'loading'" class="m-0 pt-1 font-mono">Loading…</p>
    <p v-else-if="query.state.value.status === 'failed'" class="m-0 pt-1 text-caution-text">
      Couldn't load the reservation: {{ describeApiError(query.state.value.error) }}
    </p>
    <div v-else-if="r" class="flex flex-col gap-2 pt-1 font-mono">
      <dl class="m-0 grid grid-cols-[max-content_minmax(0,1fr)] gap-x-3 gap-y-0.5">
        <template v-for="f in facts" :key="f.key">
          <dt class="text-text-4">{{ f.key }}</dt>
          <dd class="m-0 break-all text-text-2">
            <RouterLink v-if="f.to" :to="f.to" class="text-readout underline">{{
              f.text
            }}</RouterLink>
            <template v-else>{{ f.text }}</template>
          </dd>
        </template>
      </dl>
      <table v-if="r.values.length" class="w-full border-collapse">
        <caption class="sr-only">
          Provider values
        </caption>
        <thead>
          <tr class="text-left text-text-4">
            <th class="pr-2 font-normal">Field</th>
            <th class="pr-2 font-normal">Requested</th>
            <th class="pr-2 font-normal">Confirmed</th>
            <th class="font-normal">Accepted</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in r.values" :key="row.field" class="border-t border-hairline-faint">
            <td class="pr-2 text-text-3">{{ row.field }}</td>
            <td
              v-for="(c, i) in valueCells(row)"
              :key="i"
              class="pr-2 break-all"
              :class="TONE_CLASS[c.tone]"
              :title="c.title"
            >
              {{ c.text }}
            </td>
          </tr>
        </tbody>
      </table>
      <ul v-if="audit.length" ref="listEl" class="m-0 list-none p-0" aria-label="Provider audit">
        <li v-for="a in audit" :key="a.id">
          {{ clock(a.recorded_at) }} · {{ sentenceCase(a.action) }} · {{ sentenceCase(a.outcome) }}
        </li>
      </ul>
      <div ref="moreEl" class="contents">
        <ApButton
          v-if="hasEarlier"
          size="compact"
          variant="ghost"
          class="self-start"
          @click="showEarlier"
          >Show earlier</ApButton
        >
      </div>
      <!-- a11y B6: always mounted so a failed Show earlier is announced; cleared as it starts again. -->
      <p role="alert" class="m-0 text-caution-text">
        {{
          query.moreError.value
            ? `Couldn't load more: ${describeApiError(query.moreError.value)}`
            : ""
        }}
      </p>
    </div>
  </details>
  <!-- Its contact id comes from the reservation, so opening it reads the reservation too. -->
  <ContactRecordView
    :mission-id="missionId"
    :contact-id="r ? r.reservation.scheduled_contact_id : undefined"
    @open="opened = true"
  />
</template>
