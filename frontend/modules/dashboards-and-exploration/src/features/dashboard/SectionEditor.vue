<script setup lang="ts">
import { ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { SectionInput } from "./contracts";

const props = defineProps<{ initial: SectionInput; creating: boolean; pending: boolean }>();
const emit = defineEmits<{ apply: [input: SectionInput]; cancel: [] }>();
const section = ref<SectionInput>({ ...props.initial });
</script>

<template>
  <form
    class="space-y-4"
    @submit.prevent="
      section.title.trim() && emit('apply', { ...section, title: section.title.trim() })
    "
  >
    <CadenceTextField id="section-title" v-model="section.title" label="Title" required />
    <CadenceTextField id="section-description" v-model="section.description" label="Description" />
    <CadenceCheckbox v-model="section.collapsed_by_default"
      >Collapsed when the dashboard opens</CadenceCheckbox
    >
    <footer class="flex justify-end gap-2 border-t border-base-300/60 pt-4">
      <CadenceButton variant="quiet" size="sm" @click="emit('cancel')">Cancel</CadenceButton>
      <CadenceButton
        type="submit"
        variant="primary"
        size="sm"
        :loading="pending"
        :disabled="!section.title.trim()"
      >
        {{ creating ? "Add section" : "Apply" }}
      </CadenceButton>
    </footer>
  </form>
</template>
