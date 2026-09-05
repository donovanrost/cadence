<script setup lang="ts">
import {
  DropdownMenuContent,
  DropdownMenuPortal,
  DropdownMenuRoot,
  DropdownMenuTrigger,
} from "reka-ui";
import { CadencePrimitiveChild } from "./cadence_primitive_child.js";

defineOptions({ inheritAttrs: false });

const props = defineProps<{
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
  sideOffset?: number;
}>();

const emit = defineEmits<{
  "update:open": [open: boolean];
}>();
</script>

<template>
  <DropdownMenuRoot v-slot="{ open }" @update:open="emit('update:open', $event)">
    <DropdownMenuTrigger as-child>
      <CadencePrimitiveChild contract-name="CadenceModalMenu trigger" :enforce-attrs="[]">
        <slot name="trigger" :open="open"></slot>
      </CadencePrimitiveChild>
    </DropdownMenuTrigger>

    <DropdownMenuPortal>
      <DropdownMenuContent
        as-child
        :side="props.side"
        :align="props.align"
        :side-offset="props.sideOffset"
      >
        <CadencePrimitiveChild contract-name="CadenceModalMenu content" :enforce-attrs="[]">
          <slot name="content" :open="open"></slot>
        </CadencePrimitiveChild>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
