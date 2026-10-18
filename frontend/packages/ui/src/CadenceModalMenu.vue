<script setup lang="ts">
import {
  DropdownMenuContent,
  DropdownMenuPortal,
  DropdownMenuRoot,
  DropdownMenuTrigger,
} from "reka-ui";
import { computed } from "vue";
import { CadencePrimitiveChild } from "./cadence_primitive_child";

defineOptions({ inheritAttrs: false });

const props = defineProps<{
  side?: "top" | "right" | "bottom" | "left";
  align?: "start" | "center" | "end";
  sideOffset?: number;
}>();

const positioning = computed(() => ({
  ...(props.side === undefined ? {} : { side: props.side }),
  ...(props.align === undefined ? {} : { align: props.align }),
  ...(props.sideOffset === undefined ? {} : { sideOffset: props.sideOffset }),
}));

const emit = defineEmits<{
  "update:open": [open: boolean];
  closeAutoFocus: [event: Event];
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
        v-bind="positioning"
        @close-auto-focus="emit('closeAutoFocus', $event)"
      >
        <CadencePrimitiveChild contract-name="CadenceModalMenu content" :enforce-attrs="[]">
          <slot name="content" :open="open"></slot>
        </CadencePrimitiveChild>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
