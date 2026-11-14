<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { plural, useNow, ApButton, ApCallout, ApTag } from "@/ui";
import ConfirmDialog from "../compose/ConfirmDialog.vue";
import type { Group } from "../groups/show.ts";
import {
  NO_ACCESS_RELEASE,
  releaseOnContact,
  resultLine,
  unbookedSheetBody,
} from "../groups/release.ts";

/**
 * U46 named release (DECISIONS #84; lead: Uplink's contact view only). Armed groups never go into
 * a hand-started contact by themselves; an operator sends them by naming it, after ux's danger
 * sheet. It sends every armed group for that spacecraft, oldest first (api), and counts them.
 */
const props = defineProps<{ group: Group; missionId: MissionId; canRelease: boolean }>();
const emit = defineEmits<{ changed: [] }>();
const now = useNow();

const contact = computed(() => props.group.uplink?.contact ?? null);
const armed = computed(() => contact.value?.armed_group_ids ?? []);
/** The block describes the group's first target (api); only that spacecraft's members go. */
const spacecraft = computed(
  () => props.group.uplink?.spacecraft?.name ?? props.group.targets[0]?.name ?? null,
);
const body = computed(() => {
  const c = contact.value;
  return c
    ? unbookedSheetBody(
        spacecraft.value,
        c.station.code ?? c.station.name,
        c.started_by?.name ?? null,
        c.started_at ?? null,
        armed.value.length,
        now.value,
      )
    : "";
});

const dialog = ref<InstanceType<typeof ConfirmDialog> | null>(null);
const busy = ref(false);
const lines = ref<readonly string[]>([]);
async function release() {
  const c = contact.value;
  if (!c || busy.value || !(await dialog.value?.ask())) return;
  busy.value = true;
  lines.value = [];
  const at = new Date();
  try {
    const out = await releaseOnContact(props.missionId, c.realized_contact_id, armed.value, true, {
      at,
      booked: false,
    });
    if (out.kind === "done") {
      const rs = out.release.results;
      lines.value = rs.every((r) => r.outcome === "released")
        ? [`Released ${plural(rs.length, "command group")}.`]
        : rs.map(
            (r) =>
              `${r.command_group_id === props.group.id ? "This request" : "Another request"}: ${resultLine(r, { at, booked: false })}`,
          );
      emit("changed");
    } else
      lines.value = [
        out.kind === "refused" ? out.text : "Not released: the contact wasn't confirmed.",
      ];
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApCallout v-if="contact && armed.length" tone="caution">
    <span class="flex flex-wrap items-center gap-2">
      <ApTag state="caution" label="Not a booked pass" />
      <span>
        Armed commands don't go to this contact on their own. Release them here only if you mean to.
      </span>
    </span>
    <p v-if="!canRelease" class="m-0 text-sm text-text-3">{{ NO_ACCESS_RELEASE }}</p>
    <p v-if="busy" class="m-0 text-sm text-text-2">Releasing…</p>
    <p v-for="(line, i) in lines" :key="i" class="m-0 text-sm text-text-2">{{ line }}</p>
    <template v-if="canRelease" #action>
      <ApButton size="compact" variant="danger" :disabled="busy" @click="release"
        >Release here</ApButton
      >
    </template>
  </ApCallout>
  <ConfirmDialog
    ref="dialog"
    question="Release into a contact that isn't a booked pass?"
    :body="body"
    confirm="Release to this contact"
    cancel="Cancel"
  />
</template>
