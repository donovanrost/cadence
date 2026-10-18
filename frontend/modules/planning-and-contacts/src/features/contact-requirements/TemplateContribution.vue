<script setup lang="ts">
import { computed } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { TemplatePage } from "./templates";
import { templatePresentation } from "./template-presentation";
import { useTemplateWorkflow } from "./template-workflow-state";
import OpsContactRequirementTemplate from "./OpsContactRequirementTemplate.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: TemplatePage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const {
  model,
  draft,
  selected,
  pending,
  uncertain,
  disabled,
  notice,
  feedback,
  confirmed,
  submit,
  update,
  lifecycle,
  refresh,
} = useTemplateWorkflow(
  () => props.page,
  () => props.port,
  () => props.readPort,
);
const presentation = computed(() => templatePresentation(model.value, draft.value, selected.value));
</script>
<template>
  <section id="requirement-template-contribution" class="min-w-0 space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pt-4">
      <p id="requirement-template-notice" role="status" class="text-sm text-base-content/65">
        {{ notice }}
      </p>
      <button
        id="requirement-template-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="!!pending"
        @click="refresh"
      >
        Refresh template ledger
      </button>
    </div>
    <p
      v-if="uncertain"
      id="requirement-template-unconfirmed"
      role="alert"
      class="mx-4 border border-warning/40 p-3 text-sm"
    >
      Further actions are paused. Refresh to recover the page receipt.
    </p>
    <p
      v-if="feedback"
      id="requirement-template-feedback"
      role="alert"
      class="mx-4 text-sm text-error"
    >
      {{ feedback }}
    </p>
    <p
      v-if="model.can_manage && model.spacecraft.total === 0"
      id="requirement-template-no-spacecraft"
      class="mx-4 text-sm"
    >
      This mission has no spacecraft available for a recurring need.
    </p>
    <p
      v-if="confirmed"
      id="requirement-template-receipt"
      class="mx-4 min-w-0 break-all border border-success/40 p-3 text-sm"
    >
      {{ confirmed.action }} · completed · {{ confirmed.receipt.result.reference.template_id }} ·
      v{{ confirmed.receipt.result.reference.version }} ·
      {{ confirmed.receipt.result.reference.lifecycle_state }}
    </p>
    <nav aria-label="Template ledger pages" class="mx-4 flex flex-wrap items-center gap-3 text-sm">
      <span>Templates · page {{ model.templates.page }}</span>
      <button
        v-if="model.templates.page > 1"
        id="requirement-templates-previous"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('templates-page', { page: model.templates.page - 1 })"
      >
        Previous templates
      </button>
      <button
        v-if="model.templates.more"
        id="requirement-templates-next"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('templates-page', { page: model.templates.page + 1 })"
      >
        Next templates
      </button>
    </nav>
    <nav
      v-if="model.can_manage"
      aria-label="Template spacecraft choices"
      class="mx-4 flex flex-wrap items-center gap-3 text-sm"
    >
      <span
        >Spacecraft · page {{ model.spacecraft.page }} · {{ model.spacecraft.total }} total</span
      >
      <button
        v-if="model.spacecraft.page > 1"
        id="template-spacecraft-previous"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('spacecraft-page', { page: model.spacecraft.page - 1 })"
      >
        Previous spacecraft
      </button>
      <button
        v-if="model.spacecraft.page * 25 < model.spacecraft.total"
        id="template-spacecraft-next"
        class="btn btn-ghost btn-sm"
        :disabled="disabled || !!pending"
        @click="submit('spacecraft-page', { page: model.spacecraft.page + 1 })"
      >
        Next spacecraft
      </button>
    </nav>
    <fieldset class="m-0 min-w-0 border-0 p-0" :disabled="disabled">
      <legend class="sr-only">Recurring contact needs</legend>
      <OpsContactRequirementTemplate
        v-bind="presentation"
        @validate-template="update('validate-template', $event)"
        @create-template="update('create-template', $event)"
        @pause-template="lifecycle('pause-template', $event)"
        @activate-template="lifecycle('activate-template', $event)"
        @close-template="lifecycle('close-template', $event)"
      />
    </fieldset>
  </section>
</template>
<style scoped>
#requirement-template-contribution :deep(.fieldset),
#requirement-template-contribution :deep(.fieldset > label),
#requirement-template-contribution :deep(input) {
  min-width: 0;
}
#requirement-template-contribution :deep(input) {
  max-width: 100%;
}
#requirement-template-contribution :deep(.fieldset:has(input[type="datetime-local"])) {
  grid-column: 1 / -1;
}
#requirement-template-contribution :deep(input[type="datetime-local"]) {
  font-size: 0.75rem;
  padding-inline: 0.5rem;
}
@media (max-width: 639px) {
  #requirement-template-contribution :deep(.grid) {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
