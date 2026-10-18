<script setup lang="ts">
import { CollapsibleRoot } from "reka-ui";
import { computed, provide, ref, toRef, watch } from "vue";
import { CadencePrimitiveChild } from "./cadence_primitive_child";

defineOptions({ inheritAttrs: false });

const props = withDefaults(
  defineProps<{
    open: boolean;
    contentId: string;
    disabled?: boolean;
    clientSeeded?: boolean;
    seedEpoch?: string | number;
    unmountOnHide?: boolean;
  }>(),
  {
    disabled: false,
    clientSeeded: false,
    unmountOnHide: true,
  },
);

if (props.clientSeeded && props.seedEpoch === undefined) {
  throw new Error("CadenceCollapsible client-seeded mode requires seedEpoch");
}

const emit = defineEmits<{
  "request-change": [open: boolean];
}>();

const clientOpen = ref(props.open);
const effectiveOpen = computed(() => (props.clientSeeded ? clientOpen.value : props.open));

watch(
  () => props.seedEpoch,
  () => {
    if (!props.clientSeeded) return;
    if (props.seedEpoch === undefined) {
      throw new Error("CadenceCollapsible client-seeded mode requires seedEpoch");
    }

    clientOpen.value = props.open;
  },
);

const requestChange = (open: boolean) => {
  if (props.clientSeeded) clientOpen.value = open;
  emit("request-change", open);
};

provide("cadence-collapsible", { contentId: toRef(props, "contentId") });
</script>

<template>
  <CollapsibleRoot
    :open="effectiveOpen"
    :disabled="props.disabled"
    :unmountOnHide="props.unmountOnHide"
    as-child
    @update:open="requestChange"
  >
    <CadencePrimitiveChild
      contract-name="CadenceCollapsible"
      :enforce-attrs="['data-state', 'data-disabled']"
    >
      <slot :open="effectiveOpen" :disabled="props.disabled"></slot>
    </CadencePrimitiveChild>
  </CollapsibleRoot>
</template>
