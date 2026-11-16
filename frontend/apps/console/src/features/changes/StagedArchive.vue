<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApInlineConfirm, ApMenuButton, ApMenuItem } from "@/ui";
import { stageChange } from "./actions.ts";
import { refusalOutcome, type RefusalOutcome } from "./refusals.ts";
import { refreshConfigState } from "./useConfigState.ts";

/**
 * ux U82: 'Archive…' for a transport or a ground station, staged like any change (the kind's delete).
 * It sits in a row's ⋯ menu or among an edit page's header actions, never as a primary button. The
 * in-place confirm opens on Cancel. An in-use refusal comes back to the page (emit 'refused') to show
 * in the confirm's place with its lines; any other refusal reads inside the confirm, which stays open.
 */
const props = defineProps<{
  missionId: MissionId;
  kind: "transport" | "ground_station";
  entityId: string;
  /** As people read it: 'INU S-band', 'Inuvik · INU'. */
  name: string;
  surface: string;
  variant: "menu" | "button";
}>();
const emit = defineEmits<{ refused: [outcome: RefusalOutcome] }>();
const router = useRouter();
const confirming = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
const menu = ref<HTMLElement | null>(null);
const menuTrigger = () => menu.value?.querySelector("button") ?? null;
const summary = () =>
  props.kind === "transport" ? `Archive transport ${props.name}` : `Archive station ${props.name}`;

async function archive() {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const r = await stageChange(props.missionId, {
      summary: summary(),
      source: { surface: props.surface },
      ops: [{ kind: props.kind, action: "delete", entity_id: props.entityId }],
    });
    if (r.ok) {
      confirming.value = false;
      refreshConfigState(props.missionId);
      return void (await router.push({ name: "setup.changes" }));
    }
    const outcome = refusalOutcome(r.error, "staged");
    if (!outcome.uses && !outcome.closing) return void (failure.value = outcome.sentence);
    confirming.value = false;
    emit("refused", outcome);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <span v-if="variant === 'menu'" ref="menu" class="inline-flex">
    <ApMenuButton :label="`More actions for ${name}`">
      <ApMenuItem @select="confirming = true">Archive…</ApMenuItem>
    </ApMenuButton>
  </span>
  <ApInlineConfirm
    v-model:open="confirming"
    action="Stage archive"
    :busy="busy"
    busy-reason="Staging…"
    :refusal="failure"
    :return-focus="variant === 'menu' ? menuTrigger : null"
    @confirm="archive"
    @cancel="failure = null"
  >
    <template v-if="variant === 'button'" #trigger="{ attrs }">
      <ApButton size="compact" variant="ghost" v-bind="attrs">Archive…</ApButton>
    </template>
    Stage archiving {{ name }}? Once the change set is applied, it can't be chosen for new routes or
    passes. Its history stays.
  </ApInlineConfirm>
</template>
