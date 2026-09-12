<script setup lang="ts">
import { watch } from "vue";
import { useFormWorkflow } from "../../shared/useFormWorkflow";
import { validationResult } from "../../shared/validation-receipt";
import type { FormPort } from "../../shared/form-workflow.contracts";
import type { ReadContext } from "../../shared/read-contracts";
import type { Page, RoutingRuleForm, RoutingRuleOptions } from "./routing-new.contracts";
import CommsRoutingNew from "./CommsRoutingNew.vue";
const props = defineProps<{
  page: Page;
  form: RoutingRuleForm;
  options: RoutingRuleOptions;
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
    <CommsRoutingNew
      :page="page"
      :form="form"
      :options="options"
      :feedback="workflow.feedback.value"
      @validate="workflow.validate"
      @save="workflow.save"
    />
  </fieldset>
</template>
