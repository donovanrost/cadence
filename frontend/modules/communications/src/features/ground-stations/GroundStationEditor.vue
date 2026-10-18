<script setup lang="ts">
import { watch } from "vue";
import { useFormWorkflow } from "../../shared/useFormWorkflow";
import { validationResult } from "../../shared/validation-receipt";
import type { FormPort } from "../../shared/form-workflow.contracts";
import type { ReadContext } from "../../shared/read-contracts";
import type { Page, GroundStationForm } from "./ground-station-form.contracts";
import CommsGroundStationForm from "./CommsGroundStationForm.vue";
const props = defineProps<{
  page: Page;
  mode: "new" | "edit";
  form: GroundStationForm;
  port: FormPort;
  context: ReadContext;
}>();
const workflow = useFormWorkflow(
  () => props.port,
  () => props.context,
  validationResult,
);
watch(() => props.form, workflow.reset, { flush: "sync" });
</script>
<template>
  <fieldset class="contents" :disabled="workflow.saving.value">
    <CommsGroundStationForm
      :page="page"
      :form="form"
      :mode="mode"
      :feedback="workflow.feedback.value"
      @validate="workflow.validate"
      @save="workflow.save"
    />
  </fieldset>
</template>
