<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref, watch } from "vue";
import { plural, useNow, ApButton, ApCallout, ApTag } from "@/ui";
import ConfirmDialog from "../compose/ConfirmDialog.vue";
import { fetchGroups } from "../groups/api.ts";
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
/**
 * The block describes the group's first target (api); only that spacecraft's members go. Named
 * from api's uplink.spacecraft, or the group's only target; never guessed (U25).
 */
const spacecraft = computed(
  () =>
    props.group.uplink?.spacecraft?.name ??
    (props.group.targets.length === 1 ? (props.group.targets[0]?.name ?? null) : null),
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

/** ux: other requests are named as the request list names them (their title). */
async function titlesOf(ids: readonly string[]): Promise<ReadonlyMap<string, string>> {
  if (ids.every((id) => id === props.group.id)) return new Map();
  const rows = await fetchGroups(props.missionId, {});
  return new Map(rows.ok ? rows.value.map((g) => [g.id, g.title]) : []);
}

const dialog = ref<InstanceType<typeof ConfirmDialog> | null>(null);
const busy = ref(false);
const lines = ref<readonly string[]>([]);
/** a11y B6 (#243): all released is a status; any refused or failed request makes it an alert. */
const linesFailed = ref(false);
/**
 * a11y B6/A5 (#243, ca-ux, ux B4): the result stays after the callout goes (a clean release empties
 * armed on the refetch). Focus follows to it only if it was in the callout when it went (the
 * Release button, after the confirm); a partial release keeps the callout, so focus stays.
 */
const shown = computed(() => contact.value !== null && armed.value.length > 0);
const calloutEl = ref<HTMLElement | null>(null);
const statusEl = ref<HTMLElement | null>(null);
const alertEl = ref<HTMLElement | null>(null);
watch(
  shown,
  async (now, was) => {
    if (now || !was || !calloutEl.value?.contains(document.activeElement)) return;
    await nextTick();
    (linesFailed.value ? alertEl.value : statusEl.value)?.focus();
  },
  { flush: "pre" },
);
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
      linesFailed.value = !rs.every((r) => r.outcome === "released");
      if (!linesFailed.value) lines.value = [`Released ${plural(rs.length, "request")}.`];
      else {
        const titles = await titlesOf(rs.map((r) => r.command_group_id));
        const ctx = { at, booked: false, spacecraft: spacecraft.value };
        lines.value = rs.map(
          (r) =>
            `${r.command_group_id === props.group.id ? "This request" : (titles.get(r.command_group_id) ?? "Another request")}: ${resultLine(r, ctx)}`,
        );
      }
      emit("changed");
    } else {
      linesFailed.value = true;
      lines.value = [
        out.kind === "refused" ? out.text : "Not released: the contact wasn't confirmed.",
      ];
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div v-if="shown" ref="calloutEl">
    <ApCallout tone="caution">
      <span class="flex flex-wrap items-center gap-2">
        <ApTag state="caution" label="Not a booked pass" />
        <span>
          Armed commands don't go to this contact on their own. Release them here only if you mean
          to.
        </span>
      </span>
      <p v-if="!canRelease" class="m-0 text-sm text-text-3">{{ NO_ACCESS_RELEASE }}</p>
      <p v-if="busy" class="m-0 text-sm text-text-2">Releasing…</p>
      <template v-if="canRelease" #action>
        <ApButton size="compact" :disabled="busy" disabled-reason="Releasing…" @click="release"
          >Release commands…</ApButton
        >
      </template>
    </ApCallout>
  </div>
  <!-- a11y B6 (#243, ca-ux): two regions that are always there (outside the callout, which goes
       once nothing is armed), so the role never changes with the content and the last result
       stays until the next release: all released is a status, anything else an alert. -->
  <div ref="statusEl" role="status" tabindex="-1" class="flex flex-col outline-none">
    <template v-if="!linesFailed">
      <p v-for="(line, i) in lines" :key="i" class="m-0 text-sm text-text-2">{{ line }}</p>
    </template>
  </div>
  <div ref="alertEl" role="alert" tabindex="-1" class="flex flex-col outline-none">
    <template v-if="linesFailed">
      <p v-for="(line, i) in lines" :key="i" class="m-0 text-sm text-text-2">{{ line }}</p>
    </template>
  </div>
  <ConfirmDialog
    ref="dialog"
    question="Release into a contact that isn't a booked pass?"
    :body="body"
    :confirm="`Release ${plural(armed.length, 'request')}`"
    cancel="Cancel"
  />
</template>
