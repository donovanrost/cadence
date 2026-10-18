<script setup lang="ts">
import { computed, inject, reactive, ref } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import { catalogUploadKey } from "./upload-contract";

import type { CatalogUploadFormProps, UploadEntry } from "./CatalogUploadForm.contracts";
const props = defineProps<CatalogUploadFormProps>();

const emit = defineEmits<{
  validate: [payload: Record<string, Record<string, string>>];
  save: [];
  "cancel-upload": [payload: { ref: string }];
}>();

const allFields = [...props.form.primary_fields, ...props.form.secondary_fields];
const transport = inject(catalogUploadKey, null);
const submitting = computed(() => transport?.busy.value ?? false);
const submissionError = computed(() => transport?.error.value);

const values = reactive<Record<string, string>>(
  Object.fromEntries(allFields.map((field) => [field.key, field.value])),
);

const visibleInput = ref<HTMLInputElement | null>(null);
const selectedEntries = ref<UploadEntry[]>([]);
const entries = computed(() =>
  transport
    ? props.upload.entries
    : selectedEntries.value.length > 0
      ? selectedEntries.value
      : props.upload.entries,
);
const progress = computed(() => entries.value[0]?.progress ?? 0);
const uploadValid = computed(
  () => props.upload.errors.length === 0 && entries.value.every((entry) => entry.valid),
);

const validationErrors = computed(() => props.upload.errors);

const formValues = () =>
  Object.fromEntries(allFields.map((field) => [field.key, values[field.key] ?? ""]));

const validate = () => {
  if (transport) {
    transport.validate(formValues());
    return;
  }
  emit("validate", { [props.form.name]: formValues() });
};

const selectFiles = (event: Event) => {
  const target = event.target as HTMLInputElement;
  const files = target.files;

  if (files && files.length > 0) {
    if (transport) {
      transport.select(Array.from(files), formValues());
      return;
    }
    selectedEntries.value = Array.from(files).map((file) => ({
      ref: `local-${file.name}`,
      client_name: file.name,
      client_size: file.size,
      client_type: file.type,
      progress: 0,
      done: false,
      valid: true,
      preflighted: false,
      errors: [],
    }));
    validate();
  }
};

const cancelUpload = (ref: string) => {
  selectedEntries.value = selectedEntries.value.filter((entry) => entry.ref !== ref);

  if (visibleInput.value) visibleInput.value.value = "";

  if (transport) transport.cancel(ref);
  else emit("cancel-upload", { ref });
};

const syncHiddenFormFields = () => {
  const uploadForm = visibleInput.value?.form;
  if (!uploadForm) return false;

  uploadForm.querySelectorAll("[data-catalog-upload-field]").forEach((field) => field.remove());

  for (const field of allFields) {
    const hiddenField = document.createElement("input");
    hiddenField.type = "hidden";
    hiddenField.name = field.name;
    hiddenField.value = values[field.key] ?? "";
    hiddenField.setAttribute("data-catalog-upload-field", field.key);
    uploadForm.appendChild(hiddenField);
  }

  return true;
};

const submitUpload = () => {
  if (props.submit_disabled || submitting.value) return;
  if (transport) {
    transport.submit(formValues());
    return;
  }
  if (props.submit_disabled || !syncHiddenFormFields()) return;
  emit("save");
};
</script>

<template>
  <section :id="form.card.id ?? undefined" :class="form.card.class">
    <div :class="form.card.body_class">
      <p :class="form.card.title_class">{{ form.card.title }}</p>

      <div :class="form.content_class ?? undefined">
        <p v-if="form.description" :class="form.description.class">
          {{ form.description.text }}
        </p>

        <form :id="form.id" :class="form.class" @submit.prevent="submitUpload">
          <p v-if="submitting" id="catalog-upload-pending" role="status">
            Uploading and requesting the revision import…
          </p>
          <p
            v-if="submissionError"
            id="catalog-upload-error"
            role="alert"
            :class="form.error_class"
          >
            {{ submissionError }}
          </p>
          <div :class="form.primary_fields_class">
            <CadenceField
              v-for="field in form.primary_fields"
              :key="field.key"
              :control-id="field.id"
              :wrapper-class="field.wrapper_class"
              :label="field.label"
              :label-class="field.label_class"
            >
              <textarea
                v-if="field.type === 'textarea'"
                :id="field.id"
                v-model="values[field.key]"
                :name="field.name"
                :class="field.input_class"
                @input="validate"
              ></textarea>
              <input
                v-else
                :id="field.id"
                v-model="values[field.key]"
                :name="field.name"
                :type="field.type"
                :class="field.input_class"
                @input="validate"
              />
              <template #errors>
                <p v-for="error in field.errors" :key="error" :class="field.error_class">
                  {{ error }}
                </p>
              </template>
            </CadenceField>
          </div>

          <CadenceField
            v-for="field in form.secondary_fields"
            :key="field.key"
            :control-id="field.id"
            :wrapper-class="field.wrapper_class"
            :label="field.label"
            :label-class="field.label_class"
          >
            <textarea
              v-if="field.type === 'textarea'"
              :id="field.id"
              v-model="values[field.key]"
              :name="field.name"
              :class="field.input_class"
              @input="validate"
            ></textarea>
            <input
              v-else
              :id="field.id"
              v-model="values[field.key]"
              :name="field.name"
              :type="field.type"
              :class="field.input_class"
              @input="validate"
            />
            <template #errors>
              <p v-for="error in field.errors" :key="error" :class="field.error_class">
                {{ error }}
              </p>
            </template>
          </CadenceField>

          <label v-if="form.file_input.wrapper_class" :class="form.file_input.wrapper_class">
            <input
              :id="form.file_input.id"
              ref="visibleInput"
              type="file"
              :name="form.file_input.name"
              :accept="upload.accept || undefined"
              :multiple="upload.max_entries > 1"
              :class="form.file_input.class"
              :aria-invalid="!uploadValid"
              @change="selectFiles"
            />
          </label>
          <input
            v-else
            :id="form.file_input.id"
            ref="visibleInput"
            type="file"
            :name="form.file_input.name"
            :accept="upload.accept || undefined"
            :multiple="upload.max_entries > 1"
            :class="form.file_input.class"
            :aria-invalid="!uploadValid"
            @change="selectFiles"
          />

          <ul v-if="entries.length > 0" :class="form.entries.list_class">
            <li v-for="entry in entries" :key="entry.ref" :class="form.entries.item_class">
              <span :class="form.entries.name_class">
                {{ entry.client_name }} ({{ entry.client_type || "unknown" }})
              </span>
              <progress
                :value="progress"
                max="100"
                :class="form.entries.progress_class"
                aria-label="Upload progress"
              />
              <button
                type="button"
                :class="form.entries.remove_class"
                @click="cancelUpload(entry.ref)"
              >
                {{ form.entries.remove_label }}
              </button>
            </li>
          </ul>

          <div
            v-for="error in validationErrors"
            :key="`${error.code}-${error.message}`"
            role="alert"
            :class="form.error_class"
          >
            {{ error.message }}
          </div>

          <div v-if="detected_importer.status === 'detected'" :class="form.importer.detected_class">
            <span :class="form.importer.icon_class"></span>
            Detected importer:
            <span :class="form.importer.name_class">{{ detected_importer.display_name }}</span>
          </div>
          <div
            v-else-if="detected_importer.status === 'unsupported'"
            role="alert"
            :class="form.error_class"
          >
            No importer supports this file. Choose a supported YAML or XTCE catalog file.
          </div>
          <div v-else :class="form.importer.empty_class">
            Select a file to see the detected importer.
          </div>

          <div v-if="form.actions_class" :class="form.actions_class">
            <button
              :id="form.submit.id ?? undefined"
              type="submit"
              :class="form.submit.class"
              :disabled="submit_disabled || submitting"
            >
              {{ form.submit.label }}
            </button>
          </div>
          <button
            v-else
            :id="form.submit.id ?? undefined"
            type="submit"
            :class="form.submit.class"
            :disabled="submit_disabled || submitting"
          >
            {{ form.submit.label }}
          </button>
        </form>
      </div>
    </div>
  </section>
</template>
