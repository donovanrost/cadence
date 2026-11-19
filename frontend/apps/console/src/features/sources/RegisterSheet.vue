<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApRemote, ApSheet } from "@/ui";
import { sourceFailure } from "./present.ts";
import { blankDraft, blockedReason, registerBody, type RegisterDraft } from "./register.ts";
import RegisterFields from "./RegisterFields.vue";
import { fetchSourceOptions, registerSource } from "./writes.ts";

/** L11 W1 Register source: the server makes the id from the name; options come from R1. */
const props = defineProps<{ missionId: MissionId }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const opened = ref(false);
const options = useRemoteQuery(() => (opened.value ? props.missionId : null), fetchSourceOptions);
const ready = computed(() =>
  options.state.value.status === "ready" ? options.state.value.value : null,
);
const draft = ref<RegisterDraft>(blankDraft);
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() => blockedReason(draft.value, ready.value, busy.value));

// a11y A1: when the choices are still loading, the sheet opens on Cancel (the fields aren't there
// yet); once they load, move focus to Name unless the user is already in the form.
const form = ref<HTMLFormElement | null>(null);
let nameOnLoad = false;
watch(
  ready,
  (r) => {
    if (!r || !nameOnLoad) return;
    nameOnLoad = false;
    if (!form.value?.contains(document.activeElement)) form.value?.querySelector("input")?.focus();
  },
  { flush: "post" },
);

function open() {
  draft.value = blankDraft;
  failure.value = null;
  opened.value = true;
  nameOnLoad = ready.value === null;
  sheet.value?.open();
}
async function submit() {
  const body = registerBody(draft.value, ready.value);
  if (!body || busy.value) return;
  busy.value = true;
  try {
    const r = await registerSource(props.missionId, body);
    if (!r.ok) return void (failure.value = sourceFailure(r.error));
    sheet.value?.close();
    await router.push({ name: "setup.data-sources", params: { sourceId: r.value.id } });
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Register source" initial-focus="input">
    <ApRemote
      :state="options.state.value"
      loading-label="Loading choices…"
      @retry="options.refetch"
    >
      <template #default="{ value: o }">
        <form ref="form" class="flex flex-col gap-3" @submit.prevent="submit">
          <RegisterFields v-model="draft" :options="o" />
          <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
        </form>
      </template>
    </ApRemote>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >Register</ApButton
      >
    </template>
  </ApSheet>
</template>
