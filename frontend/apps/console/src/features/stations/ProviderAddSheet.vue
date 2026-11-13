<script setup lang="ts">
import { computed, ref } from "vue";
import { fieldErrors, useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApRemote, ApSheet } from "@/ui";
import ProviderAddFields from "./ProviderAddFields.vue";
import {
  addBody,
  addProvider,
  blankAdd,
  fetchProviderOptions,
  providerFailure,
  type AddDraft,
} from "./providers.ts";

/** L12 Add provider: bind one of this mission's account grants; bounded mode asks two more things. */
const props = defineProps<{ missionId: string }>();
const emit = defineEmits<{ added: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const opened = ref(false);
const options = useRemoteQuery(() => (opened.value ? props.missionId : null), fetchProviderOptions);
const draft = ref<AddDraft>(blankAdd);
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
const built = computed(() => addBody(draft.value));

function open() {
  draft.value = blankAdd;
  errors.value = {};
  failure.value = null;
  opened.value = true;
  sheet.value?.open();
}
async function submit() {
  const b = built.value;
  if (!b.ok || busy.value) return;
  busy.value = true;
  try {
    const r = await addProvider(props.missionId, b.body);
    if (r.ok) {
      sheet.value?.close();
      return void emit("added");
    }
    errors.value = fieldErrors(r.error);
    failure.value = Object.keys(errors.value).length > 0 ? null : providerFailure(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Add provider" initial-focus="select">
    <ApRemote
      :state="options.state.value"
      loading-label="Loading account grants…"
      @retry="options.refetch"
    >
      <template #default="{ value: o }">
        <form class="flex flex-col gap-3" @submit.prevent="submit">
          <ProviderAddFields v-model="draft" :options="o" :errors="errors" />
          <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
        </form>
      </template>
    </ApRemote>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!built.ok || busy"
        :disabled-reason="built.ok ? 'Adding…' : built.why"
        @click="submit"
        >Add provider</ApButton
      >
    </template>
  </ApSheet>
</template>
