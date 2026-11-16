<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, shallowRef, watch } from "vue";
import { describeApiError, isError, isKnown, useRemoteQuery } from "@/api/index.ts";
import { ApButton } from "@/ui";
import { fetchContactRecord, type ContactRecord } from "./records.ts";
import { clock, sentenceCase, span } from "./recordWords.ts";

/**
 * 'Contact record' (ux U74, api A13): scheduled and realized contact, paths with their bindings,
 * sources and intents, and the schedule's revisions (newest first, Show earlier). `contactId`:
 * undefined while the reservation that names it loads, null when it has none.
 */
const props = defineProps<{
  missionId: MissionId;
  contactId: string | null | undefined;
  /** ux U78: the record on its own (a hand-started contact's drawer), open from the start. */
  alone?: boolean;
}>();
const emit = defineEmits<{ open: [] }>();
const opened = ref(props.alone === true);
/** U78/U25: a missing record isn't named by its id as if that were a name. */
const failure = computed(() => {
  const s = query.state.value;
  if (s.status !== "failed") return null;
  return isError(s.error, "contact_not_found")
    ? "No contact record with this id."
    : `Couldn't load the contact record: ${describeApiError(s.error)}`;
});
const query = useRemoteQuery(
  computed(() =>
    opened.value && props.contactId ? { m: props.missionId, c: props.contactId } : null,
  ),
  (k, signal) => fetchContactRecord(k.m, k.c, null, signal),
);
const c = computed(() => (query.state.value.status === "ready" ? query.state.value.value : null));
const earlier = shallowRef<ContactRecord["revisions"]["entries"]>([]);
const cursor = ref<string | null>(null);
const moreError = ref<string | null>(null);
watch(c, (v) => {
  earlier.value = [];
  cursor.value = v?.revisions.next_cursor ?? null;
});
async function showEarlier() {
  if (!cursor.value || !props.contactId) return;
  const page = await fetchContactRecord(props.missionId, props.contactId, cursor.value);
  if (!page.ok) {
    moreError.value = `Couldn't load more: ${describeApiError(page.error)}`;
    return;
  }
  earlier.value = [...earlier.value, ...page.value.revisions.entries];
  cursor.value = page.value.revisions.next_cursor;
}
const revisions = computed(() => [...(c.value?.revisions.entries ?? []), ...earlier.value]);
const side = (s: { unrecognized: string } | string) =>
  sentenceCase(isKnown(s) ? s : s.unrecognized);
const facts = computed(() => {
  const v = c.value;
  if (!v) return [];
  const sch = v.scheduled;
  const rea = v.realized;
  return [
    [
      "Scheduled",
      sch ? `${sentenceCase(sch.lifecycle_state)} · ${span(sch.starts_at, sch.ends_at)}` : null,
    ],
    ["Scheduled contact", sch?.id ?? null],
    ["Provider contact", sch?.provider_contact_ref ?? null],
    ["Realized", rea ? sentenceCase(rea.lifecycle_state) : null],
    ["Realized at", rea?.realized_at ? clock(rea.realized_at) : null],
    ["Clock mode", rea?.clock_mode ? sentenceCase(rea.clock_mode) : null],
    ["Realized contact", rea?.id ?? null],
    ...v.sources.map((s) => [`Source (${side(s.side)})`, s.id]),
    ...v.intents.map((i) => [`Intent (${side(i.side)})`, i.id]),
  ].filter((f): f is [string, string] => f[1] !== null);
});
const onToggle = (e: Event) => {
  if (e.target instanceof HTMLDetailsElement && e.target.open) {
    opened.value = true;
    emit("open");
  }
};
</script>

<template>
  <component :is="alone ? 'div' : 'details'" class="text-xs text-text-3" @toggle="onToggle">
    <summary v-if="!alone" class="cursor-pointer font-mono uppercase">Contact record</summary>
    <p v-if="contactId === null" class="m-0 pt-1">No scheduled contact for this reservation.</p>
    <p v-else-if="!c && query.state.value.status !== 'failed'" class="m-0 pt-1 font-mono">
      Loading…
    </p>
    <p v-else-if="failure" class="m-0 pt-1 text-caution-text">{{ failure }}</p>
    <div v-else-if="c" class="flex flex-col gap-2 pt-1 font-mono">
      <dl class="m-0 grid grid-cols-[max-content_minmax(0,1fr)] gap-x-3 gap-y-0.5">
        <template v-for="[k, v] in facts" :key="k + v">
          <dt class="text-text-4">{{ k }}</dt>
          <dd class="m-0 break-all text-text-2">{{ v }}</dd>
        </template>
      </dl>
      <table v-if="c.paths.length" class="w-full border-collapse">
        <caption class="sr-only">
          Paths and bindings
        </caption>
        <thead>
          <tr class="text-left text-text-4">
            <th class="pr-2 font-normal">Path</th>
            <th class="pr-2 font-normal">Provider binding</th>
            <th class="font-normal">Transport binding</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in c.paths" :key="p.id" class="border-t border-hairline-faint align-top">
            <td class="pr-2 break-all text-text-2">
              {{ p.id }} · {{ sentenceCase(p.direction) }} · {{ side(p.side) }}
            </td>
            <td class="pr-2 break-all">
              {{ p.provider_bindings.map((b) => `${b.adapter_key} ${b.id}`).join(", ") || "none" }}
            </td>
            <td class="break-all">
              {{ p.transport_bindings.map((b) => `${b.family_key} ${b.id}`).join(", ") || "none" }}
            </td>
          </tr>
        </tbody>
      </table>
      <ul v-if="revisions.length" class="m-0 list-none p-0" aria-label="Schedule revisions">
        <li v-for="rev in revisions" :key="rev.revision">
          r{{ rev.revision }} · {{ span(rev.starts_at, rev.ends_at) }} ·
          {{ sentenceCase(rev.lifecycle_state).toLowerCase() }}
        </li>
      </ul>
      <ApButton v-if="cursor" size="compact" variant="ghost" class="self-start" @click="showEarlier"
        >Show earlier</ApButton
      >
      <p v-if="moreError" class="m-0 text-caution-text">{{ moreError }}</p>
      <p v-if="c.truncated" class="m-0">More paths, sources or intents than shown.</p>
    </div>
  </component>
</template>
