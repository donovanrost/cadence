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
defineOptions({ inheritAttrs: false });
const props = defineProps<{ directory: RequirementDirectory; readPort: OpsPageReadPort }>();
const initial = props.directory,
  directory = shallowRef(initial),
  pending = ref(false),
  notice = ref("");
let active = true,
  generation = 0;
const presentation = computed(() => requirementDirectoryPresentation(directory.value));
watch(
  () => props.directory,
  (next) => {
    if (!requirementDataEqual(next, initial)) {
      generation++;
      pending.value = false;
      directory.value = next;
    }
  },
);
onBeforeUnmount(() => {
  active = false;
  generation++;
});
async function refresh() {
  if (pending.value) return;
  const n = ++generation;
  pending.value = true;
  try {
    const value = await props.readPort.read();
    if (!active || n !== generation) return;
    const admitted = admitRequirementDirectory(value, initial.context, initial.query);
    if (!admitted) throw Error("Unavailable directory");
    directory.value = admitted;
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
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pt-4">
      <p id="requirement-directory-notice" role="status" class="text-sm text-base-content/65">
        {{ notice }}
      </p>
      <button
        id="requirement-directory-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="pending"
        @click="refresh"
      >
        Refresh requirements
      </button>
    </div>
    <OpsContactRequirementList v-bind="presentation" />
  </section>
</template>
