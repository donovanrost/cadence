<script setup lang="ts">
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitRequirementDirectory,
  requirementDataEqual,
  type RequirementDirectory,
} from "./requirement-directory";
import { requirementDirectoryPresentation } from "./requirement-directory-presentation";
import OpsContactRequirementList from "./OpsContactRequirementList.vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ directory: RequirementDirectory; readPort: OpsPageReadPort }>();
const initial = props.directory,
  currentDirectory = shallowRef(initial),
  pending = ref(false),
  notice = ref("");
let active = true,
  generation = 0;
const presentation = computed(() => requirementDirectoryPresentation(currentDirectory.value));
watch(
  () => props.directory,
  (next) => {
    if (!requirementDataEqual(next, initial)) {
      generation++;
      pending.value = false;
      currentDirectory.value = next;
    }
  },
);
onBeforeUnmount(() => {
  active = false;
  generation++;
});
useOpsHeader("/missions/:mission_id/ops/requirements", () => ({
  description:
    "Declare the mission outcome first; Cadence searches every provider route and keeps the evidence.",
  primary: {
    id: "declare-need",
    label: "Declare need",
    icon: "hero-plus",
    href: href("/missions/:mission_id/ops/requirements/new", {
      mission_id: currentDirectory.value.context.mission_id,
    }),
  },
  refresh: { run: refresh, pending: pending.value },
}));
async function refresh() {
  if (pending.value) return;
  const n = ++generation;
  pending.value = true;
  try {
    const value = await props.readPort.read();
    if (!active || n !== generation) return;
    const admitted = admitRequirementDirectory(value, initial.context, initial.query);
    if (!admitted) throw Error("Unavailable directory");
    currentDirectory.value = admitted;
    notice.value = "Requirement evidence refreshed.";
  } catch {
    if (active && n === generation)
      notice.value = "Refresh failed. Previous requirement evidence is retained.";
  } finally {
    if (active && n === generation) pending.value = false;
  }
}
</script>
<template>
  <section id="requirement-directory-contribution" class="min-w-0 space-y-4">
    <p
      v-if="notice"
      id="requirement-directory-notice"
      role="status"
      class="text-sm text-base-content/70"
    >
      {{ notice }}
    </p>
    <OpsContactRequirementList v-bind="presentation" />
  </section>
</template>
