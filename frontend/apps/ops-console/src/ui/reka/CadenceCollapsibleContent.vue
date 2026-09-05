<script setup lang="ts">
import { CollapsibleContent } from "reka-ui";
import { inject, type Ref } from "vue";
import { CadencePrimitiveChild } from "./cadence_primitive_child.js";

defineOptions({ inheritAttrs: false });

const collapsible = inject<{ contentId: Readonly<Ref<string>> }>("cadence-collapsible");
if (!collapsible) throw new Error("CadenceCollapsibleContent requires CadenceCollapsible");
</script>

<template>
  <CollapsibleContent as-child>
    <CadencePrimitiveChild
      contract-name="CadenceCollapsibleContent"
      :id="collapsible.contentId.value"
      :enforce-attrs="['id', 'hidden', 'data-state', 'data-disabled']"
    >
      <slot></slot>
    </CadencePrimitiveChild>
  </CollapsibleContent>
</template>
