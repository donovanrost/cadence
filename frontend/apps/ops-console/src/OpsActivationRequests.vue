<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { ref, watch } from "vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";

type Page = {
  id: string;
  heading: string;
  subtitle: string;
  list: {
    card_id: string;
    id: string;
    empty: {
      id: string;
      copy: string;
    };
  };
};

type SelectedRequest = {
  activation_request_id: string;
  binding_set_id: string;
  binding_set_version: number;
};

type FormField = {
  id: string;
  name: string;
  type: "hidden" | "textarea";
  value: string;
};

type DecisionAction = {
  id: string;
  name: string;
  value: "approved" | "rejected";
  label: string;
};

type DecisionForm = {
  panel_id: string;
  id: string;
  request_id: FormField;
  reason: FormField & {
    label: string;
    required: boolean;
  };
  actions: {
    reject: DecisionAction;
    approve: DecisionAction;
  };
};

type ActivationRequest = {
  __dom_id: string;
  activation_request_id: string;
  binding_set_id: string;
  binding_set_version: number;
  status: {
    label: string;
  };
  requester_display: string;
  review: {
    id: string;
    label: string;
  };
};

type Decision = "approved" | "rejected";

const props = defineProps<{
  page: Page;
  selected: SelectedRequest | null;
  form: DecisionForm;
  activation_requests: ActivationRequest[];
}>();

const emit = defineEmits<{
  decide: [
    payload: {
      activation_decision: { request_id: string; reason: string };
      decision: Decision;
    },
  ];
}>();

const selectedRequest = ref<SelectedRequest | null>(props.selected);
const rationale = ref(props.form.reason.value);

watch(
  () => props.selected,
  (requestId, previousRequestId) => {
    // A new selection owns a fresh server form. Patches for the same selection
    // must not overwrite rationale typed locally after the last server render.
    selectedRequest.value = requestId;
    if (requestId?.activation_request_id !== previousRequestId?.activation_request_id) {
      rationale.value = props.form.reason.value;
    }
  },
);

const review = (request: ActivationRequest) => {
  selectedRequest.value = {
    activation_request_id: request.activation_request_id,
    binding_set_id: request.binding_set_id,
    binding_set_version: request.binding_set_version,
  };
  rationale.value = "";
};

const decide = (event: SubmitEvent) => {
  const decision = (event.submitter as HTMLButtonElement | null)?.value;

  if (decision !== "approved" && decision !== "rejected") return;

  emit("decide", {
    activation_decision: {
      request_id: selectedRequest.value?.activation_request_id ?? "",
      reason: rationale.value,
    },
    decision,
  });
};
</script>

<template>
  <section :id="page.id" class="space-y-4">
    <CadencePageHeading>
      <template #title>{{ page.heading }}</template>
      <template #description>{{ page.subtitle }}</template>
    </CadencePageHeading>

    <CadenceCard
      :id="page.list.card_id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <div :id="page.list.id" class="divide-y divide-base-300/30">
        <div
          :id="page.list.empty.id"
          class="hidden only:block py-8 text-center text-sm text-base-content/60"
        >
          {{ page.list.empty.copy }}
        </div>
        <div
          v-for="request in activation_requests"
          :id="request.__dom_id"
          :key="request.activation_request_id"
          class="flex items-center justify-between gap-4 py-3"
        >
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-mono text-xs text-base-content/60">
                {{ request.binding_set_id }}@{{ request.binding_set_version }}
              </span>
              <span
                class="rounded border border-warning/30 bg-warning/10 px-2 py-0.5 text-[0.625rem] font-semibold uppercase tracking-wide text-warning"
              >
                {{ request.status.label }}
              </span>
            </div>
            <p class="mt-1 text-sm text-base-content/70">
              Requested by {{ request.requester_display }}
            </p>
          </div>
          <button
            :id="request.review.id"
            type="button"
            class="btn btn-ghost btn-sm"
            @click="review(request)"
          >
            {{ request.review.label }}
          </button>
        </div>
      </div>
    </CadenceCard>

    <CadenceCard
      v-if="selectedRequest"
      :id="form.panel_id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <form :id="form.id" @submit.prevent="decide">
        <div class="fieldset mb-3">
          <label>
            <input
              :id="form.request_id.id"
              :name="form.request_id.name"
              :type="form.request_id.type"
              :value="selectedRequest.activation_request_id"
              class="w-full input"
            />
          </label>
        </div>
        <CadenceField
          wrapper-class="fieldset mb-3"
          :label="form.reason.label"
          label-class="hud-label block mb-1.5"
        >
          <textarea
            :id="form.reason.id"
            v-model="rationale"
            :name="form.reason.name"
            :required="form.reason.required"
            class="w-full textarea"
          ></textarea>
        </CadenceField>
        <div class="mt-3 flex justify-end gap-2">
          <button
            :id="form.actions.reject.id"
            type="submit"
            :name="form.actions.reject.name"
            :value="form.actions.reject.value"
            class="btn btn-ghost btn-sm"
          >
            {{ form.actions.reject.label }}
          </button>
          <button
            :id="form.actions.approve.id"
            type="submit"
            :name="form.actions.approve.name"
            :value="form.actions.approve.value"
            class="btn btn-primary btn-sm"
          >
            {{ form.actions.approve.label }}
          </button>
        </div>
      </form>
    </CadenceCard>
  </section>
</template>
