<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter, type RouteLocationRaw } from "vue-router";
import { isKnown, useRemoteQuery } from "@/api";
import {
  failureOutcome,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApSelect } from "@/ui";
import {
  EGRESS_NOT_READY,
  egressReady,
  errorWords,
  fetchProviderOptions,
  stageEgressRefusal,
  type DeliveryChoice,
  type ProviderErrorPath,
} from "./provider-options.ts";
import ProviderTransportPreview from "./ProviderTransportPreview.vue";
import { blockedReason, formFromDocument, providerOp } from "./provider-transport.ts";

/**
 * A provider-managed transport (comms parity 2): name, then provider → service → delivery, each
 * narrowing the next (api's provider-options read over domain's derive/3), with the settings
 * Cadence will derive shown before staging. Stages through the change set (transport kind).
 */
const props = defineProps<{
  missionId: MissionId;
  entityId: string | null;
  document: Readonly<Record<string, unknown>>;
  done: RouteLocationRaw;
}>();
const router = useRouter();
const start = formFromDocument(props.document);
const name = ref(start.name);
const providerId = ref(start.providerId);
const serviceId = ref(start.serviceId);
const deliveryId = ref(start.deliveryId);
// A changed choice clears the ones that depended on it.
watch(providerId, () => ((serviceId.value = ""), (deliveryId.value = "")));
watch(serviceId, () => (deliveryId.value = ""));
const options = useRemoteQuery(
  () => ({
    missionId: props.missionId,
    providerId: providerId.value || null,
    serviceProfileId: serviceId.value || null,
    deliveryProfileId: deliveryId.value || null,
  }),
  fetchProviderOptions,
);
const ready = computed(() =>
  options.state.value.status === "ready" ? options.state.value.value : null,
);
const asOptions = (list: readonly { id: string; name: string }[] | undefined) =>
  (list ?? []).map((c) => ({ value: c.id, label: c.name }));
/** #993: a delivery without usable egress addresses stays listed, disabled, saying why. */
const deliveryOptions = (list: readonly DeliveryChoice[] | undefined) =>
  (list ?? []).map((c) =>
    egressReady(c)
      ? { value: c.id, label: c.name }
      : { value: c.id, label: `${c.name} (${EGRESS_NOT_READY})`, disabled: true },
  );
/** derive's refusal on a field (a coded one in the console's words), or null. */
const fieldError = (path: ProviderErrorPath) => {
  const e = ready.value?.errors.find((x) => x.path !== null && isKnown(x.path) && x.path === path);
  return e ? errorWords(e) : null;
};
const general = computed(() => ready.value?.errors.filter((e) => e.path === null) ?? []);
const form = computed(() => ({
  name: name.value,
  providerId: providerId.value,
  serviceId: serviceId.value,
  deliveryId: deliveryId.value,
}));
const blocked = computed(() => blockedReason(form.value, ready.value));
const busy = ref(false);
const failure = ref<string | null>(null);
/** #413: a refusal's way out (e.g. Open the report), beside its words. */
const failureLink = ref<FailureOutcome["link"] | null>(null);

async function stage() {
  const opts = ready.value;
  if (blocked.value !== null || !opts || busy.value) return;
  const op = providerOp(props.entityId, props.document, form.value, opts);
  failureLink.value = null;
  if (!op) return void (failure.value = "Those choices are no longer on offer. Choose again.");
  if (op.changes?.length === 0) return void (failure.value = "Nothing changed yet.");
  busy.value = true;
  failure.value = null;
  try {
    const summary = props.entityId
      ? `${form.value.name.trim()} · provider settings`
      : `Add transport ${form.value.name.trim()}`;
    const result = await stageChange(props.missionId, {
      summary,
      source: { surface: "transports" },
      ops: [op],
    });
    if (!result.ok) {
      const egress = stageEgressRefusal(result.error);
      const outcome = failureOutcome(result.error, "staged");
      failure.value = egress ? `Nothing was staged. ${egress}` : outcome.sentence;
      failureLink.value = outcome.link ?? null;
      return;
    }
    refreshConfigState(props.missionId);
    await router.push(props.done);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="stage">
    <ApField v-model="name" label="Name" required />
    <ApSelect
      v-model="providerId"
      label="Provider"
      placeholder="Choose…"
      required
      :options="asOptions(ready?.providers)"
      :error="fieldError('mission_provider_id') ?? fieldError('mission_provider_version')"
    />
    <ApSelect
      v-model="serviceId"
      label="Service profile"
      placeholder="Choose…"
      required
      :disabled="!providerId"
      :options="asOptions(ready?.services)"
      :error="fieldError('service_profile_ref')"
    />
    <ApSelect
      v-model="deliveryId"
      label="Delivery profile"
      placeholder="Choose…"
      required
      :disabled="!serviceId"
      :options="deliveryOptions(ready?.deliveries)"
      :error="fieldError('delivery_profile_ref')"
    />
    <ApCallout v-for="(e, i) in general" :key="i" tone="caution">{{ e.message }}</ApCallout>
    <ProviderTransportPreview v-if="ready?.preview" :preview="ready.preview" />
    <!-- a11y B6 (#243): a refused stage is the person's own act refused: an alert. -->
    <ApCallout v-if="failure" tone="caution" role="alert"
      >{{ failure }}
      <template v-if="failureLink" #action>
        <ApButton size="compact" :to="failureLink.to">{{ failureLink.label }}</ApButton>
      </template>
    </ApCallout>
    <div class="flex flex-wrap gap-2">
      <ApButton
        type="submit"
        variant="primary"
        :disabled="blocked !== null || busy"
        :disabled-reason="busy ? 'Staging…' : (blocked ?? '')"
        >Stage change</ApButton
      >
      <ApButton :to="done">Cancel</ApButton>
    </div>
    <p class="m-0 text-sm text-text-3">Nothing is live until the change set is applied.</p>
  </form>
</template>
