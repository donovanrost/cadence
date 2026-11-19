<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApCallout } from "@/ui";
import type { Group } from "../groups/show.ts";
import { argChanges, fetchBrief, overwriteCallouts, type Brief } from "./brief.ts";
import OwnValuesTable from "./OwnValuesTable.vue";
import { useCatalogArgs } from "./useCatalogArgs.ts";
import { overridesOf, readoutLines } from "./ownValues.ts";
import { resolvedLines } from "../groups/resolved.ts";

/**
 * A1 value changes (CommandFlow A1): for each command with arguments, `mode 1 → 3` per argument
 * (current values tallied across targets), and callouts where a prior request set a target
 * differently. Briefs are read for at most LIMIT targets.
 */
const props = defineProps<{ group: Group }>();
const LIMIT = 40;
const scope = useMissionScope();
const withArgs = computed(() =>
  [...props.group.commands]
    // U68: a command whose blank arguments took defaults has rows too.
    .filter((c) => c.argument_values_json.trim() !== "{}" || c.resolved_arguments?.length)
    .sort((a, b) => a.position - b.position),
);
const targets = computed(() => props.group.targets.slice(0, LIMIT));
const key = computed(() =>
  withArgs.value.length
    ? `${props.group.id}|${withArgs.value.map((c) => c.position).join(",")}`
    : null,
);
let failed = 0;
const unread = ref(0);
const briefs = useRemoteQuery(key, async (_k, signal) => {
  const m = scope.value.mission.id;
  failed = 0;
  const byPosition = await Promise.all(
    withArgs.value.map(async (c) => {
      const ids = targets.value.flatMap((t) =>
        t.members.filter((mem) => mem.position === c.position).map((mem) => mem.request_id),
      );
      const results = await Promise.all(ids.map((id) => fetchBrief(m, id, signal)));
      failed += results.filter((r) => !r.ok).length;
      return [c.position, results.flatMap((r) => (r.ok ? [r.value] : []))] as const;
    }),
  );
  unread.value = failed;
  return { ok: true as const, value: new Map<number, Brief[]>(byPosition) };
});
const nameOf = (id: string) => props.group.targets.find((t) => t.spacecraft_id === id)?.name ?? id;
/** ux C2: targets with their own values; units and ranges come from the catalog's command. */
const argsOf = useCatalogArgs(
  computed(() => scope.value.mission.id),
  computed(() => props.group),
);
const rows = computed(() => {
  const s = briefs.state.value;
  if (s.status !== "ready") return [];
  return withArgs.value.map((c) => {
    const bs = s.value.get(c.position) ?? [];
    const overrides = overridesOf(c, props.group);
    const args = argsOf(c.command_id);
    const unit = (name: string) => args.find((a) => a.name === name)?.unit ?? null;
    return {
      position: c.position,
      name: c.name ?? c.command_id,
      command: c,
      overrides,
      args,
      lines: argChanges(bs).flatMap((ch) =>
        readoutLines(ch, overrides, props.group.target_count, unit(ch.name), nameOf).map(
          (text, i) => ({ key: `${ch.name}:${i}`, text, note: i === 0 ? ch.note : null }),
        ),
      ),
      callouts: overwriteCallouts(bs, c.argument_values_json, nameOf),
      resolved: resolvedLines(c.resolved_arguments, nameOf),
      read: bs.length,
    };
  });
});
</script>

<template>
  <div v-if="withArgs.length" class="flex flex-col gap-2 border-t border-hairline px-4 py-3">
    <p
      v-if="briefs.state.value.status === 'loading'"
      class="m-0 font-mono text-xs text-text-4 uppercase"
    >
      Reading current values…
    </p>
    <template v-for="r in rows" :key="r.position">
      <p class="m-0 font-mono text-sm font-semibold text-readout">{{ r.name }}</p>
      <ul class="m-0 list-none p-0">
        <li v-for="l in r.lines" :key="l.key" class="font-mono text-md text-readout">
          {{ l.text }}<span v-if="l.note" class="text-sm text-text-3"> · {{ l.note }}</span>
        </li>
      </ul>
      <!-- ux U68: where the server's value differs from what was entered. -->
      <p v-for="line in r.resolved" :key="line" class="m-0 font-mono text-sm text-text-3">
        {{ line }}
      </p>
      <!-- ux C2: what each target with its own values gets (not for a single target). -->
      <OwnValuesTable
        v-if="r.overrides.length && group.target_count > 1"
        :command="r.command"
        :overrides="r.overrides"
        :args="r.args"
        :name-of="nameOf"
      />
      <ApCallout v-for="line in r.callouts" :key="line" tone="caution">{{ line }}</ApCallout>
    </template>
    <p v-if="unread" class="m-0 font-mono text-xs text-caution-text">
      Couldn't read current values for {{ unread }} {{ unread === 1 ? "request" : "requests" }}.
    </p>
    <p v-if="group.targets.length > LIMIT" class="m-0 font-mono text-xs text-text-4">
      Current values from the first {{ LIMIT }} of {{ group.targets.length }} targets.
    </p>
  </div>
</template>
