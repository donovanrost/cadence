<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApPanel, ApTextarea } from "@/ui";
import type { TemplateDetail } from "./api.ts";
import {
  transitionFailure,
  transitionTemplate,
  VERBS,
  verbsFor,
  type TemplateVerb,
} from "./lifecycle.ts";

/** L2 Pause… / Resume… / Close…: each confirms with a required reason (as requirements' P4). */
const props = defineProps<{ missionId: MissionId; template: TemplateDetail }>();
const emit = defineEmits<{ moved: [] }>();
const verb = ref<TemplateVerb | null>(null);
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() =>
  busy.value ? "Working…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
function open(v: TemplateVerb) {
  verb.value = v;
  reason.value = "";
  error.value = failure.value = null;
}
async function confirm() {
  if (!verb.value || blocked.value !== null) return;
  busy.value = true;
  try {
    const r = await transitionTemplate(props.missionId, props.template.id, verb.value, {
      expected_version: props.template.version,
      reason: reason.value.trim(),
    });
    if (r.ok) {
      verb.value = null;
      return void emit("moved");
    }
    error.value = fieldErrors(r.error)["reason"] ?? null;
    failure.value = error.value ? null : transitionFailure(r.error);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div v-if="!verb && verbsFor(template.state).length > 0" class="flex flex-wrap gap-2">
    <ApButton v-for="v in verbsFor(template.state)" :key="v" @click="open(v)">{{
      VERBS[v].button
    }}</ApButton>
  </div>
  <ApPanel v-else-if="verb" index="T9" :title="VERBS[verb].title">
    <div class="flex max-w-[640px] flex-col gap-3">
      <p class="m-0 text-md text-text-2">{{ VERBS[verb].sentence }}</p>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <div class="flex flex-wrap gap-2">
        <ApButton
          :variant="verb === 'close' ? 'danger' : 'primary'"
          :disabled="blocked !== null"
          :disabled-reason="blocked ?? ''"
          @click="confirm"
          >{{ VERBS[verb].confirm }}</ApButton
        >
        <ApButton variant="ghost" @click="verb = null">Back</ApButton>
      </div>
    </div>
  </ApPanel>
</template>
