<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref, watch } from "vue";
import { useSession } from "@/shell";
import { ApCallout, ApPanel, plural, refocusFirst } from "@/ui";
import { discardChangeSet, failureOutcome, withdrawChange, type PreviewItem } from "./actions.ts";
import ChangeConflict from "./ChangeConflict.vue";
import { conflictRow } from "./rebase.ts";
import ChangeOps from "./ChangeOps.vue";
import ChangeRowHead from "./ChangeRowHead.vue";
import DiscardConfirm from "./DiscardConfirm.vue";
import type { Change, ChangeSet, ConfigState } from "./shapes.ts";

/** K1: one row per staged change, collapsed; expanded shows what each op touches. */
const props = defineProps<{
  missionId: MissionId;
  config: ConfigState;
  changeSet: ChangeSet;
  /** The Conflicts check's items by op id (rebase.ts conflictOps). */
  conflicts: ReadonlyMap<string, readonly PreviewItem[]>;
}>();
const conflicting = (change: Change) =>
  change.ops.filter((o) => props.conflicts.has(o.id)).map((o) => o.id);
const rowOf = (change: Change) =>
  conflictRow(
    conflicting(change).flatMap((id) => props.conflicts.get(id) ?? []),
    `r${props.changeSet.base_revision}`,
  );
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
// a11y A5: Withdraw, Discard mine and a conflict choice remove the focused control; once the set
// re-reads, focus the row now at that place (the next, else the last). An emptied set unmounts
// this list, and ChangesScreen lands on Nothing staged.
let settleAt: number | null = null;
const settleOn = (change: Change) => {
  settleAt = Math.max(0, props.changeSet.changes.indexOf(change));
};
const settle = (change: Change) => {
  settleOn(change);
  emit("changed");
};
watch(
  () => props.changeSet.changes,
  () => {
    if (settleAt === null) return;
    const rows = document.querySelectorAll<HTMLElement>("[data-change-row]");
    refocusFirst(rows[Math.min(settleAt, rows.length - 1)]);
    settleAt = null;
  },
  { flush: "post" },
);
const withdraw = (change: Change) => {
  settleOn(change);
  return run(() => withdrawChange(props.missionId, change.id));
};
const discard = () => {
  settleAt = 0;
  return run(() => discardChangeSet(props.missionId, props.changeSet.id, props.changeSet.version));
};
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
      <DiscardConfirm
        :changes="changeSet.changes"
        :user-id="session.user.id"
        :discard-any="config.permissions.has('config.discard_any')"
        :busy="busy"
        @discard="discard"
      />
    </template>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <ul class="m-0 list-none p-0">
      <li
        v-for="change in changeSet.changes"
        :key="change.id"
        class="border-t border-hairline first:border-t-0"
      >
        <ChangeRowHead
          :change="change"
          :can-withdraw="changeSet.state === 'open' && mayRemove(change)"
          :open="open.has(change.id)"
          :busy="busy"
          @withdraw="withdraw(change)"
          @toggle="toggle(change.id)"
        />
        <ChangeConflict
          v-if="changeSet.state === 'open' && conflicting(change).length > 0"
          :mission-id="missionId"
          :op-ids="conflicting(change)"
          :row="rowOf(change)"
          :can-act="mayRemove(change)"
          @done="settle(change)"
        />
        <ChangeOps v-if="open.has(change.id)" :change="change" />
      </li>
    </ul>
  </ApPanel>
</template>
