<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, shallowRef, watch } from "vue";
import { describeApiError, useRemoteQuery } from "@/api/index.ts";
import { ApButton } from "@/ui";
import ContactRecordView from "./ContactRecordView.vue";
import { fetchReservation, type Reservation } from "./records.ts";
import { holdsFocus, landOnFirstNew } from "./pageFocus.ts";
import { clock, sentenceCase, TONE_CLASS, valueCells, withVersion } from "./recordWords.ts";

/**
 * The pass's reservation and contact records (ux U74, api A11/A13) as two collapsed Technical
 * details disclosures in mono key/values. Nothing is read until one is opened.
 */
const props = defineProps<{ missionId: MissionId; passId: string; providerName: string | null }>();
const opened = ref(false);
const query = useRemoteQuery(
  computed(() => (opened.value ? { m: props.missionId, pass: props.passId } : null)),
  (k, signal) => fetchReservation(k.m, k.pass, null, signal),
);
const r = computed(() => (query.state.value.status === "ready" ? query.state.value.value : null));
/** Earlier audit pages (Show earlier), appended below the first. */
const earlier = shallowRef<Reservation["audit"]["entries"]>([]);
const cursor = ref<string | null>(null);
const moreError = ref<string | null>(null);
watch(r, (v) => {
  earlier.value = [];
  cursor.value = v?.audit.next_cursor ?? null;
});
const listEl = ref<HTMLElement | null>(null);
const moreEl = ref<HTMLElement | null>(null);
async function showEarlier() {
  if (!cursor.value) return;
  const hadFocus = holdsFocus(moreEl.value);
  const firstNew = audit.value.length;
  const page = await fetchReservation(props.missionId, props.passId, cursor.value);
  if (!page.ok) {
    moreError.value = `Couldn't load more: ${describeApiError(page.error)}`;
    return;
  }
  earlier.value = [...earlier.value, ...page.value.audit.entries];
  cursor.value = page.value.audit.next_cursor;
  if (cursor.value === null) await landOnFirstNew(listEl.value, firstNew, hadFocus);
}
const facts = computed(() => {
  const v = r.value?.reservation;
  if (!v) return [];
  const id = (x: { id: string; version: number | null } | null) =>
    x ? withVersion(x.id, x.version) : null;
  return [
    ["Reservation", v.id],
    ["Provider revision", v.provider_revision === null ? null : String(v.provider_revision)],
    ["State", sentenceCase(v.lifecycle_state)],
    ["Provider", withVersion(props.providerName ?? v.provider.id, v.provider.version)],
    ["Transport", id(v.transport)],
    ["Plan", id(v.plan)],
    ["Requirement", id(v.requirement)],
    ["Scheduled contact", v.scheduled_contact_id],
    ["Last reconciled", v.last_reconciled_at ? clock(v.last_reconciled_at) : null],
  ].filter((f): f is [string, string] => f[1] !== null);
});
const audit = computed(() => [...(r.value?.audit.entries ?? []), ...earlier.value]);
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
        <template v-for="[k, v] in facts" :key="k">
          <dt class="text-text-4">{{ k }}</dt>
          <dd class="m-0 break-all text-text-2">{{ v }}</dd>
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
          v-if="cursor"
          size="compact"
          variant="ghost"
          class="self-start"
          @click="showEarlier"
          >Show earlier</ApButton
        >
      </div>
      <p v-if="moreError" role="alert" class="m-0 text-caution-text">{{ moreError }}</p>
    </div>
  </details>
  <!-- Its contact id comes from the reservation, so opening it reads the reservation too. -->
  <ContactRecordView
    :mission-id="missionId"
    :contact-id="r ? r.reservation.scheduled_contact_id : undefined"
    @open="opened = true"
  />
</template>
