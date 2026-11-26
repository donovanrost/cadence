<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApSheet } from "@/ui";
import GrantNarrowFields from "./GrantNarrowFields.vue";
import GrantRefusal from "./GrantRefusal.vue";
import { narrowChanges, narrowDraft, type NarrowDraft } from "./grant-narrow.ts";
import { narrowFailure } from "./grant-refusals.ts";
import { narrowedLine, type Worded } from "./grant-words.ts";
import { narrowGrant, operationIds, type Grant } from "./grants.ts";

/**
 * U105 Narrow…: one person, at once. The sheet starts at what the grant allows and offers only
 * less; Narrow is disabled until a value is narrower ("Choose less than the grant allows now.").
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ narrowed: [said: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const grant = ref<Grant | null>(null);
const draft = ref<NarrowDraft>({ actions: [], hours: "", contacts: "", concurrency: "", days: "" });
const refusal = ref<Worded | null>(null);
const busy = ref(false);
const ops = operationIds();
const built = computed(() => (grant.value ? narrowChanges(grant.value, draft.value) : null));

function open(g: Grant) {
  grant.value = g;
  draft.value = narrowDraft(g);
  refusal.value = null;
  sheet.value?.open();
}
async function submit() {
  const g = grant.value;
  const b = built.value;
  if (!g || !b?.ok || busy.value) return;
  busy.value = true;
  refusal.value = null;
  try {
    const key = `narrow:${g.id}:${JSON.stringify(b.changes)}`;
    const r = await narrowGrant(props.missionId, g, b.changes, ops(key));
    if (r.ok) {
      sheet.value?.close();
      return void emit("narrowed", narrowedLine(r.value.grant));
    }
    refusal.value = narrowFailure(r.error, g);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Narrow the grant" initial-focus="input">
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <GrantNarrowFields
        v-if="grant"
        v-model="draft"
        :grant="grant"
        :errors="built && !built.ok ? built.errors : {}"
      />
      <GrantRefusal :refusal="refusal" />
      <p class="m-0 text-sm text-text-3">
        It takes effect at once. Narrowing only takes access away, so no approval is needed.
      </p>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!built?.ok || busy"
        :disabled-reason="busy ? 'Narrowing…' : built && !built.ok ? built.why : undefined"
        @click="submit"
        >Narrow</ApButton
      >
    </template>
  </ApSheet>
</template>
