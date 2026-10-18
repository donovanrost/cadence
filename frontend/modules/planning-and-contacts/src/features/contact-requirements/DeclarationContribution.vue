<script setup lang="ts">
import { computed } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { declarationResultHref, type DeclarationPage } from "./declaration";
import { declarationPresentation } from "./declaration-presentation";
import { useDeclarationWorkflow } from "./declaration-workflow-state";
import OpsContactRequirementNew from "./OpsContactRequirementNew.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: DeclarationPage;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
const {
  model,
  operation,
  draft,
  selected,
  pending,
  uncertain,
  created,
  disabled,
  notice,
  feedback,
  update,
  submit,
  refresh,
} = useDeclarationWorkflow(
  () => props.page,
  () => props.port,
  () => props.readPort,
);
const presentation = computed(() =>
  declarationPresentation(model.value, draft.value, feedback.value, selected.value),
);
</script>
<template>
  <section id="requirement-declaration-contribution" class="min-w-0 space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pt-4">
      <p id="requirement-declaration-notice" role="status" class="text-sm text-base-content/65">
        {{ notice }}
      </p>
      <button
        id="requirement-declaration-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="!!pending"
        @click="refresh"
      >
        Refresh declaration context
      </button>
    </div>
    <p
      v-if="uncertain"
      id="requirement-declaration-unconfirmed"
      role="alert"
      class="mx-4 border border-warning/40 p-3 text-sm"
    >
      Further actions are paused. Refresh to recover the action receipt.
    </p>
    <p v-if="!model.can_declare" id="requirement-declaration-empty" class="mx-4 text-sm">
      This mission has no spacecraft available for a contact need.
    </p>
    <div
      v-if="created && operation?.action === 'save' && operation.status === 'completed'"
      id="requirement-declaration-receipt"
      class="mx-4 flex flex-wrap items-center gap-3 border border-success/40 p-3"
    >
      <p class="min-w-0 break-all text-sm">
        Requirement {{ operation.receipt.result.requirement_id }} · version
        {{ operation.receipt.result.requirement_version }}
      </p>
      <button
        id="requirement-declaration-open"
        class="btn btn-primary btn-sm"
        @click="port.navigate(declarationResultHref(model, operation))"
      >
        Open requirement
      </button>
    </div>
    <nav
      id="requirement-spacecraft-pages"
      aria-label="Spacecraft choices"
      class="mx-4 flex flex-wrap items-center gap-3 text-sm"
    >
      <span
        >Spacecraft · page {{ model.spacecraft.page }} · {{ model.spacecraft.total }} total</span
      >
      <button
        v-if="model.spacecraft.page > 1"
        id="requirement-spacecraft-previous"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('spacecraft-page', { page: model.spacecraft.page - 1 })"
      >
        Previous spacecraft
      </button>
      <button
        v-if="model.spacecraft.page * 25 < model.spacecraft.total"
        id="requirement-spacecraft-next"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('spacecraft-page', { page: model.spacecraft.page + 1 })"
      >
        Next spacecraft
      </button>
    </nav>
    <fieldset class="m-0 min-w-0 border-0 p-0" :disabled="disabled">
      <legend class="sr-only">Contact need declaration</legend>
      <OpsContactRequirementNew
        v-bind="presentation"
        @validate="update('validate', $event)"
        @save="update('save', $event)"
      />
    </fieldset>
  </section>
</template>
