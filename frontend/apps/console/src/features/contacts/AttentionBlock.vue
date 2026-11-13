<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import { RouterLink } from "vue-router";
import { describeApiError, isError } from "@/api/index.ts";
import { ApButton, ApCallout, ApTextarea } from "@/ui";
import { attentionWords, type Attention } from "@/features/now/index.ts";
import {
  ACTION_TEXT_MAX,
  acknowledgeAttention,
  attentionErrorWords,
  resolutionRecord,
  resolveAttention,
  whatToDo,
  type AttentionOutcome,
} from "./attention.ts";

/**
 * D2 attention block (ux U32): the open conflict in words, the resolution record, the provider's
 * last answer, what to do, and Acknowledge / Resolve…. A write that didn't land says so (U20).
 */
const props = defineProps<{ missionId: MissionId; attention: Attention }>();
const emit = defineEmits<{ changed: [] }>();

const words = computed(() => attentionWords(props.attention));
const record = computed(() => resolutionRecord(props.attention));
const todo = computed(() => whatToDo(props.attention));
const acknowledged = computed(() => props.attention.state === "acknowledged");
/** The plan day of the pass; pass_resolution items always carry starts_at. */
const planDay = computed(() => props.attention.starts_at?.slice(0, 10));

const busy = ref(false);
const notice = ref<{ tone: "caution" | "info"; text: string } | null>(null);

function settle(o: AttentionOutcome, done: string): boolean {
  if (o.status === "done") {
    notice.value = { tone: "info", text: done };
    emit("changed");
    return true;
  }
  if (o.status === "unclear") {
    notice.value = {
      tone: "caution",
      text: "No answer from the server, so it may or may not have saved. Reload the pass to check.",
    };
    emit("changed");
    return false;
  }
  const w = attentionErrorWords(o.error);
  notice.value = { tone: "caution", text: w.text };
  if (w.refresh) emit("changed");
  return false;
}

async function acknowledge() {
  busy.value = true;
  try {
    settle(await acknowledgeAttention(props.missionId, props.attention), "Acknowledged.");
  } finally {
    busy.value = false;
  }
}

const dialog = ref<HTMLDialogElement | null>(null);
const actionText = ref("");
const fieldError = ref<string | null>(null);
/** The server's limit (contacts.md: action_text ≤ 200); count down from 180 (ux). */
const left = computed(() => ACTION_TEXT_MAX - actionText.value.length);
const counter = computed(() => (left.value <= 20 ? `${left.value} left` : undefined));
const titleId = `ap-resolve-${Math.random().toString(36).slice(2, 9)}`;
function openResolve() {
  actionText.value = "";
  fieldError.value = null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("textarea")?.focus());
}
async function resolve() {
  const text = actionText.value.trim();
  if (!text) {
    fieldError.value = "Say what you did.";
    return;
  }
  busy.value = true;
  try {
    const o = await resolveAttention(props.missionId, props.attention, text);
    if (o.status === "rejected" && isError(o.error, "invalid_params")) {
      fieldError.value = describeApiError(o.error);
      return;
    }
    settle(o, "Resolved. It leaves the queue.");
    dialog.value?.close();
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <ApCallout tone="caution">
      <p class="m-0 font-semibold">{{ words.what }}</p>
      <p v-if="record" class="m-0 text-text-2">{{ record }}</p>
      <p v-if="attention.provider_message" class="m-0 font-mono text-sm text-text-2">
        “{{ attention.provider_message }}”
      </p>
      <p class="m-0">
        {{ todo.text }}
        <RouterLink
          v-if="todo.plan"
          :to="{ name: 'ops.contacts.plan', query: { day: planDay } }"
          class="max-md:hit-44 text-readout underline hover:text-bright"
          >Open the day's plan</RouterLink
        >
      </p>
      <p v-if="acknowledged" class="m-0 font-mono text-xs text-text-2 uppercase">
        Acknowledged{{
          attention.acknowledged_by?.name ? ` by ${attention.acknowledged_by.name}` : ""
        }}
      </p>
      <div class="flex flex-wrap gap-2 pt-1">
        <ApButton
          v-if="!acknowledged"
          size="compact"
          variant="secondary"
          :disabled="busy"
          @click="acknowledge"
          >Acknowledge</ApButton
        >
        <ApButton size="compact" variant="primary" :disabled="busy" @click="openResolve"
          >Resolve…</ApButton
        >
      </div>
    </ApCallout>
    <ApCallout v-if="notice" :tone="notice.tone">{{ notice.text }}</ApCallout>
    <dialog
      ref="dialog"
      :aria-labelledby="titleId"
      aria-modal="true"
      class="m-auto w-[min(560px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    >
      <form class="flex flex-col gap-3 p-5" @submit.prevent="resolve">
        <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
          Resolve
        </h2>
        <p class="m-0 text-text-2">{{ words.what }}</p>
        <ApTextarea
          v-model="actionText"
          label="What did you do?"
          required
          :maxlength="ACTION_TEXT_MAX"
          placeholder="Called Northlight; the cancel is confirmed, ticket 4471."
          :error="fieldError"
          :hint="counter"
        />
        <footer class="flex items-center justify-end gap-2 border-t border-hairline pt-3">
          <ApButton variant="ghost" type="button" @click="dialog?.close()">Cancel</ApButton>
          <ApButton variant="primary" type="submit" :disabled="busy">Resolve</ApButton>
        </footer>
      </form>
    </dialog>
  </div>
</template>
