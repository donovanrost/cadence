<script setup lang="ts">
import { ref } from "vue";
import { useSession } from "@/shell";
import { ApButton, ApCallout, ApPanel, formatShort, plural } from "@/ui";
import { discardChangeSet, failureOutcome, withdrawChange } from "./actions.ts";
import type { Change, ChangeSet, ConfigState } from "./shapes.ts";

/** K1: one row per staged change, collapsed; expanded shows what each op touches. */
const props = defineProps<{ missionId: string; config: ConfigState; changeSet: ChangeSet }>();
const emit = defineEmits<{ changed: [] }>();
const session = useSession();
const failure = ref<string | null>(null);
const busy = ref(false);

/** Withdraw and discard act on your own changes, or anyone's with config.discard_any. */
/** Discard shows only when there's something the caller may discard (ux pass 2 #6). */
const canDiscard = () =>
  props.config.permissions.has("config.discard_any") ||
  props.changeSet.changes.some((c) => c.author.id === session.user.id);
const mayRemove = (change: Change) =>
  change.author.id === session.user.id || props.config.permissions.has("config.discard_any");

async function run(
  action: () => Promise<{ ok: true } | { ok: false; error: Parameters<typeof failureOutcome>[0] }>,
) {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await action();
    if (!result.ok) failure.value = failureOutcome(result.error, "changed").sentence;
  } finally {
    busy.value = false;
    emit("changed");
  }
}
const withdraw = (change: Change) => run(() => withdrawChange(props.missionId, change.id));
const discard = () =>
  run(() => discardChangeSet(props.missionId, props.changeSet.id, props.changeSet.version));
const open = ref(new Set<string>());
function toggle(id: string) {
  const next = new Set(open.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  open.value = next;
}
</script>

<template>
  <ApPanel index="K1" title="Changes" :meta="plural(changeSet.changes.length, 'change')" flush>
    <template v-if="changeSet.state === 'open' && canDiscard()" #header>
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="busy"
        disabled-reason="Working…"
        @click="discard"
        >{{
          config.permissions.has("config.discard_any") ? "Discard all" : "Discard mine"
        }}</ApButton
      >
    </template>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <ul class="m-0 list-none p-0">
      <li
        v-for="change in changeSet.changes"
        :key="change.id"
        class="border-t border-hairline first:border-t-0"
      >
        <div
          class="grid grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-3 px-4 py-3 max-md:grid-cols-1 max-md:gap-1.5"
        >
          <span class="text-base font-semibold text-readout">{{ change.summary }}</span>
          <span class="text-sm text-text-3"
            >{{ change.author.name }} ·
            <time class="font-mono text-xs" :datetime="change.staged_at">{{
              formatShort(new Date(change.staged_at))
            }}</time></span
          >
          <ApButton
            v-if="changeSet.state === 'open' && mayRemove(change)"
            size="compact"
            variant="ghost"
            :aria-label="`Withdraw ${change.summary}`"
            :disabled="busy"
            disabled-reason="Working…"
            @click="withdraw(change)"
            >Withdraw</ApButton
          >
          <ApButton
            size="compact"
            variant="ghost"
            :aria-expanded="open.has(change.id)"
            @click="toggle(change.id)"
            >{{ open.has(change.id) ? "Hide" : "Details" }}</ApButton
          >
        </div>
        <ul
          v-if="open.has(change.id)"
          class="m-0 list-none border-t border-hairline-faint bg-vacuum px-4 py-2.5 font-mono text-sm"
        >
          <li v-for="op in change.ops" :key="op.id" class="py-0.5 text-text-2">
            <span class="text-text-4">{{ op.action }} {{ op.kind }}</span>
            {{ op.entity_id ?? "new"
            }}<template v-if="op.paths.length > 0"> · {{ op.paths.join(", ") }}</template>
          </li>
        </ul>
      </li>
    </ul>
  </ApPanel>
</template>
