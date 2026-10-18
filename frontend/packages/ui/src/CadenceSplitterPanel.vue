<script setup lang="ts">
import { SplitterPanel } from "reka-ui";
import { computed, ref } from "vue";
const props = defineProps<{
  id: string;
  order: number;
  defaultSize?: number;
  minSize?: number;
  maxSize?: number;
  sizeUnit?: "%" | "px";
  collapsible?: boolean;
  collapsedSize?: number;
}>();
const emit = defineEmits<{
  resize: [size: number, previous: number | undefined];
  collapse: [];
  expand: [];
}>();
const panel = ref<InstanceType<typeof SplitterPanel> | null>(null);
const forwarded = computed(() => ({
  id: props.id,
  order: props.order,
  ...(props.defaultSize === undefined ? {} : { defaultSize: props.defaultSize }),
  ...(props.minSize === undefined ? {} : { minSize: props.minSize }),
  ...(props.maxSize === undefined ? {} : { maxSize: props.maxSize }),
  ...(props.sizeUnit === undefined ? {} : { sizeUnit: props.sizeUnit }),
  ...(props.collapsible === undefined ? {} : { collapsible: props.collapsible }),
  ...(props.collapsedSize === undefined ? {} : { collapsedSize: props.collapsedSize }),
}));
defineExpose({
  collapse: () => panel.value?.collapse(),
  expand: () => panel.value?.expand(),
  resize: (size: number) => panel.value?.resize(size),
  getSize: () => panel.value?.getSize(),
});
</script>

<template>
  <SplitterPanel
    ref="panel"
    v-bind="forwarded"
    class="cadence-splitter-panel"
    @resize="(size, previous) => emit('resize', size, previous)"
    @collapse="emit('collapse')"
    @expand="emit('expand')"
  >
    <slot />
  </SplitterPanel>
</template>

<style scoped>
.cadence-splitter-panel {
  min-width: 0;
  min-height: 0;
  overflow: hidden;
}
</style>
