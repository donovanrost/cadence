<script setup lang="ts">
import { computed } from "vue";
import { ApSelect } from "@/ui";

/**
 * Full-size control for choosing a plane: the accessible equivalent of clicking a matrix row
 * label or an orbit, whose targets are too small for WCAG 2.5.8 (qa issue #5).
 */
const props = defineProps<{ planes: readonly number[]; selectedPlane: number | null }>();
const emit = defineEmits<{ selectPlane: [plane: number | null] }>();

const options = computed(() => [
  { value: "all", label: "All planes" },
  ...props.planes.map((plane) => ({ value: String(plane), label: `Plane ${plane}` })),
]);
const model = computed({
  get: () => (props.selectedPlane === null ? "all" : String(props.selectedPlane)),
  set: (value: string) =>
    emit("selectPlane", value === "all" || value === "" ? null : Number(value)),
});
</script>

<template>
  <ApSelect v-model="model" label="Plane" hidden-label size="compact" mono :options="options" />
</template>
