<script setup lang="ts">
import { watch } from "vue";
import { useFormWorkflow } from "../../shared/useFormWorkflow";
import type { FormPort } from "../../shared/form-workflow.contracts";
import type { ReadContext } from "../../shared/read-contracts";
import type { Page, TransportForm } from "./transport-new.contracts";
import { admitValidation } from "./validation-receipt";
import CommsTransportNew from "./CommsTransportNew.vue";
const props = defineProps<{
  page: Page;
  form: TransportForm;
  port: FormPort;
  context: ReadContext;
}>();
const workflow = useFormWorkflow(
  () => props.port,
  () => props.context,
  admitValidation,
  (result) => result.valid,
);
watch(() => props.form, workflow.reset, { flush: "sync" });
</script>
<template>
  <fieldset class="contents" :disabled="workflow.saving.value">
    <CommsTransportNew
      :page="page"
      :form="form"
      :feedback="workflow.feedback.value"
      :validation-review="workflow.outcome.value"
      @validate="workflow.validate"
      @save="workflow.save"
    />
  </fieldset>
</template>
