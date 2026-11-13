<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { organizationCapabilities, useConsoleScope, useSession } from "@/shell/index.ts";
import { ApButton, ApCallout, ApTextarea } from "@/ui";
import {
  changeEvidence,
  changeTitle,
  fieldKey,
  fieldLabel,
  pastDeadline,
  short,
  valueWords,
  type Attention,
} from "@/features/now/index.ts";
import { decideProviderChange, type ChangeDecision } from "./attention.ts";

/**
 * §11 L14 provider change on the pass (ux U44): what changed (Before → After), then Approve /
 * Reject before the deadline, or Acknowledge. Every decision needs a reason. Org admins decide
 * (`:approve_provider_changes`); members see the block without buttons.
 */
const props = defineProps<{ missionId: string; attention: Attention; now: Date }>();
const emit = defineEmits<{ changed: [] }>();

const session = useSession();
const scope = useConsoleScope();
const isAdmin = computed(() => {
  const s = scope.value;
  return s.kind === "mission" || s.kind === "organization"
    ? organizationCapabilities(session, s.organization).has("organization_admin")
    : false;
});

/** The change on show: the server's newer one replaces it after a stale refusal (U44). */
const current = ref<Attention>(props.attention);
watch(
  () => props.attention,
  (a) => (current.value = a),
);
const change = computed(() => current.value.provider_change ?? null);
const deadline = computed(() => current.value.deadline_at ?? change.value?.deadline_at ?? null);
/** A 409 that raced the deadline counts as past it (ux U44). */
const refusedPast = ref(false);
const approval = computed(() => current.value.conflict === "approval_required");
/** api 84f58b73d / ux U44: past the deadline neither decision lands; the provider's next update replaces it. */
const expired = computed(
  () => approval.value && (refusedPast.value || pastDeadline(current.value, props.now)),
);
const expiredLine = computed(() => {
  const d = deadline.value;
  const at = d ? ` at ${short(d, props.now)}` : "";
  return `The deadline passed${at}. This change stays until ${current.value.provider?.name ?? "the provider"}'s next update replaces it.`;
});

const PLACEHOLDER: Readonly<Record<ChangeDecision, string>> = {
  approve: "Why the pass can take this change",
  reject: "Why the pass can't take this change",
  acknowledge: "What you checked",
};
const LABEL: Readonly<Record<ChangeDecision, string>> = {
  approve: "Approve",
  reject: "Reject",
  acknowledge: "Acknowledge",
};

const deciding = ref<ChangeDecision | null>(null);
const reason = ref("");
const reasonError = ref<string | null>(null);
const notice = ref<{ tone: "caution" | "info"; text: string } | null>(null);
const busy = ref(false);

function start(d: ChangeDecision) {
  deciding.value = d;
  reason.value = "";
  reasonError.value = null;
  notice.value = null;
}

async function submit() {
  const d = deciding.value;
  const why = reason.value.trim();
  if (!d) return;
  if (!why) {
    reasonError.value = "Say why.";
    return;
  }
  busy.value = true;
  try {
    const o = await decideProviderChange(props.missionId, current.value, d, why);
    if (o.status === "done") {
      deciding.value = null;
      emit("changed");
      return;
    }
    if (o.status === "unclear") {
      notice.value = { tone: "caution", text: o.text };
      emit("changed");
      return;
    }
    if (o.reasonError) {
      reasonError.value = o.reasonError;
      return;
    }
    if (o.deadlinePassed) {
      // The block's own past-deadline state says it; no second notice.
      refusedPast.value = true;
      deciding.value = null;
      return;
    }
    notice.value = { tone: "caution", text: o.text };
    if (o.item) {
      current.value = o.item;
      deciding.value = null;
    } else if (o.item === null) {
      deciding.value = null;
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <ApCallout :tone="approval ? 'caution' : 'info'">
      <p class="m-0 font-semibold">{{ changeTitle(current, now) }}.</p>
      <p class="m-0 text-text-2">{{ changeEvidence(current, now) }}</p>
    </ApCallout>
    <table v-if="change && change.fields.length" class="w-full border-collapse text-sm">
      <caption class="ap-label pb-1 text-left">
        What changes
      </caption>
      <thead>
        <tr class="text-left text-text-3">
          <th scope="col" class="py-1 pr-3 font-normal">Field</th>
          <th scope="col" class="py-1 pr-3 font-normal">Before</th>
          <th scope="col" class="py-1 font-normal">After</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="f in change.fields"
          :key="typeof f.field === 'string' ? f.field : f.field.unrecognized"
          class="border-t border-hairline-faint"
        >
          <th scope="row" class="py-1 pr-3 text-left font-normal text-text-2">
            {{ fieldLabel(f) }}
            <!-- ux U44: an unnamed field's raw key and values live here, never in visible text. -->
            <details v-if="!f.label && fieldLabel(f) === 'Other'" class="text-xs text-text-3">
              <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
              <span class="block font-mono">{{ fieldKey(f) }}</span>
              <span class="block font-mono"
                >{{ f.before_json ?? "null" }} → {{ f.after_json ?? "null" }}</span
              >
            </details>
          </th>
          <td class="py-1 pr-3 font-mono text-text-2">{{ valueWords(f, f.before_json, now) }}</td>
          <td class="py-1 font-mono text-readout">{{ valueWords(f, f.after_json, now) }}</td>
        </tr>
      </tbody>
    </table>
    <ApCallout v-if="notice" :tone="notice.tone">{{ notice.text }}</ApCallout>
    <p v-if="expired" class="m-0 text-sm text-text-2">{{ expiredLine }}</p>
    <template v-else-if="current.conflict !== 'configuration_failure'">
      <p v-if="!isAdmin" class="m-0 text-sm text-text-2">Org admins decide provider changes.</p>
      <template v-else-if="deciding">
        <ApTextarea
          v-model="reason"
          :label="`Reason to ${LABEL[deciding].toLowerCase()}`"
          :placeholder="PLACEHOLDER[deciding]"
          :rows="2"
          :error="reasonError ?? undefined"
          required
        />
        <div class="flex flex-wrap gap-2">
          <ApButton
            size="compact"
            :variant="deciding === 'reject' ? 'secondary' : 'primary'"
            :disabled="busy"
            @click="submit"
            >{{ LABEL[deciding] }}</ApButton
          >
          <ApButton size="compact" variant="ghost" :disabled="busy" @click="deciding = null"
            >Cancel</ApButton
          >
        </div>
      </template>
      <div v-else class="flex flex-wrap gap-2">
        <template v-if="approval">
          <ApButton size="compact" variant="primary" @click="start('approve')">Approve…</ApButton>
          <ApButton size="compact" variant="secondary" @click="start('reject')">Reject…</ApButton>
        </template>
        <ApButton
          v-else-if="current.conflict === 'acknowledgment_required'"
          size="compact"
          variant="primary"
          @click="start('acknowledge')"
          >Acknowledge…</ApButton
        >
      </div>
    </template>
  </div>
</template>
