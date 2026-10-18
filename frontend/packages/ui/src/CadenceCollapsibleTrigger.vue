<script setup lang="ts">
import { CollapsibleTrigger } from "reka-ui";
import { inject, type Ref } from "vue";
import { CadencePrimitiveChild } from "./cadence_primitive_child";

defineOptions({ inheritAttrs: false });

const collapsible = inject<{ contentId: Readonly<Ref<string>> }>("cadence-collapsible");
if (!collapsible) throw new Error("CadenceCollapsibleTrigger requires CadenceCollapsible");
</script>

<template>
  <CollapsibleTrigger as-child>
    <CadencePrimitiveChild
      contract-name="CadenceCollapsibleTrigger"
      :aria-controls="collapsible.contentId.value"
      :enforce-attrs="[
        'type',
        'aria-controls',
        'aria-expanded',
        'data-state',
        'data-disabled',
        'disabled',
      ]"
    >
      <slot></slot>
    </CadencePrimitiveChild>
  </CollapsibleTrigger>
</template>
