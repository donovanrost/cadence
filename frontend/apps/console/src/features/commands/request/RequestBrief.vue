<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { fetchEncoding, hexBytes, type EncodingView } from "../groups/encoding.ts";
import ValueChanges from "./ValueChanges.vue";
import { radiateMeta } from "./ownValues.ts";
import { formatClock, formatDayTime, plural, ApPanel, ApTag } from "@/ui";
import { catalogRevisionWords } from "../api.ts";
import type { Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import { expiresWords, priorityTag } from "../priority.ts";

/**
 * Request header + A1 What changes + (A2 slot) + A3 What will radiate (CommandFlow C2). v1 shows the decoded
 * stack (argument JSON as sent; 64-bit safe) and, from M24, each command's payload bytes as the
 * first target's request encodes them (same values for every target).
 */
const props = defineProps<{ group: Group; nameOf: PersonName }>();
const LIMIT = 40;
const targets = computed(() => props.group.targets.slice(0, LIMIT));
const commands = computed(() => [...props.group.commands].sort((a, b) => a.position - b.position));
const release = computed(() => {
  const nb = props.group.release?.not_before;
  const when = nb
    ? `Held until ${formatClock(new Date(nb))}, then each target at its next AOS`
    : "Each target at its next AOS";
  const exp = props.group.release?.expires_at;
  return exp ? `${when}. ${expiresWords(exp)}` : when;
});
/** U68: Normal is silent; High / Low show as a neutral tag. */
const priority = computed(() => priorityTag(props.group.release?.priority));
const args = (json: string) => (json.trim() === "{}" ? "no arguments" : json);
const scope = useMissionScope();
/** One request per stack position: the first target's member at that position. */
const requestIds = computed(() => {
  const first = props.group.targets[0];
  return first ? first.members.map((m) => ({ position: m.position, id: m.request_id })) : [];
});
const encodings = useRemoteQuery(
  computed(() => (requestIds.value.length ? JSON.stringify(requestIds.value) : null)),
  async (key, signal) => {
    const ids = JSON.parse(key) as { position: number; id: string }[];
    const views = await Promise.all(
      ids.map(
        async (r) =>
          [r.position, await fetchEncoding(scope.value.mission.id, r.id, signal)] as const,
      ),
    );
    return { ok: true as const, value: new Map<number, EncodingView>(views) };
  },
);
const pos = (n: number) => String(n + 1).padStart(2, "0");
/** A3 line per command: the bytes, why they can't be shown, or that they're loading. */
const bytesLine = (position: number) => {
  const st = encodings.state.value;
  if (st.status === "loading") return { tone: "text-text-4", text: "Encoding…" };
  if (st.status !== "ready") return null;
  const v = st.value.get(position);
  if (!v) return null;
  return v.ok
    ? {
        tone: "text-readout",
        text: `${hexBytes(v.encoding.hex)} · ${plural(v.encoding.size_bytes, "byte")}`,
      }
    : { tone: "text-caution-text", text: `These bytes can't be shown: ${v.reason}.` };
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div v-if="group.log_entry" class="border-l-2 border-hairline pl-3">
      <p class="m-0 text-md text-text-2">“{{ group.log_entry }}”</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        {{ nameOf(group.requested_by.user_id) }} ·
        {{ formatDayTime(new Date(group.requested_at)) }}
      </p>
    </div>
    <ApPanel
      index="A1"
      title="What changes"
      :meta="
        [
          plural(group.target_count, 'target'),
          catalogRevisionWords(group.catalog_revision),
          group.release?.expires_at ? expiresWords(group.release.expires_at) : null,
        ]
          .filter(Boolean)
          .join(' · ')
      "
      flush
    >
      <template v-if="priority" #header><ApTag :label="priority" /></template>
      <ul class="m-0 flex list-none flex-wrap gap-x-4 gap-y-1 px-4 py-3">
        <li v-for="t in targets" :key="t.spacecraft_id" class="font-mono text-sm text-readout">
          {{ t.name ?? "Unknown spacecraft" }}
          <span class="text-text-4">SCID {{ t.scid ?? "—" }}</span>
        </li>
        <li v-if="group.targets.length > LIMIT" class="font-mono text-sm text-text-4">
          and {{ group.targets.length - LIMIT }} more
        </li>
      </ul>
      <ValueChanges :group="group" />
      <p class="m-0 border-t border-hairline px-4 py-2 text-md text-text-3">
        Release: {{ release }}.
        <ApTag v-if="priority" :label="priority" class="ml-2" />
      </p>
    </ApPanel>
    <slot name="checks" />
    <ApPanel
      index="A3"
      title="What will radiate"
      :meta="
        ['payload bytes · before transport framing', radiateMeta(group)].filter(Boolean).join(' · ')
      "
      flush
    >
      <ol class="m-0 list-none p-0">
        <li
          v-for="c in commands"
          :key="c.position"
          class="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-hairline-faint px-4 py-2 first:border-t-0"
        >
          <span class="font-mono text-xs text-text-4">{{ pos(c.position) }}</span>
          <span class="font-mono text-md font-semibold text-readout">{{
            c.name ?? c.command_id
          }}</span>
          <ApTag v-if="c.hazardous" state="crit" label="HAZ" />
          <ApTag v-else-if="c.critical" state="caution" label="CRIT" />
          <span class="min-w-0 truncate font-mono text-sm text-text-3">{{
            args(c.argument_values_json)
          }}</span>
          <!-- ux C2: the shared values above; these targets send their own instead. -->
          <ApTag
            v-if="(c.per_target ?? []).length"
            state="neutral"
            :label="`${(c.per_target ?? []).length} own values`"
          />
          <span
            v-if="bytesLine(c.position)"
            class="basis-full font-mono text-xs"
            :class="bytesLine(c.position)?.tone"
            >{{ bytesLine(c.position)?.text }}</span
          >
        </li>
      </ol>
    </ApPanel>
  </div>
</template>
