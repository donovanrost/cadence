<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CatalogUploadForm from "./CatalogUploadForm.vue";
import CadenceFormPageFrame from "@cadence/ui/CadenceFormPageFrame.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Page = {
  id: string;
  heading: string;
  breadcrumbs: Breadcrumb[];
  cancel: {
    id: string;
    label: string;
    href: string;
  };
};

type CatalogUploadFormProps = InstanceType<typeof CatalogUploadForm>["$props"];

defineProps<{
  page: Page;
  form: CatalogUploadFormProps["form"];
  upload: CatalogUploadFormProps["upload"];
  detected_importer: CatalogUploadFormProps["detected_importer"];
  submit_disabled: boolean;
}>();

const emit = defineEmits<{
  validate: [payload: Record<string, Record<string, string>>];
  save: [];
  "cancel-upload": [payload: { ref: string }];
}>();
</script>

<template>
  <CadenceFormPageFrame :id="page.id">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.heading }}</template>
    </CadencePageHeading>

    <CatalogUploadForm
      :form="form"
      :upload="upload"
      :detected_importer="detected_importer"
      :submit_disabled="submit_disabled"
      @validate="emit('validate', $event)"
      @save="emit('save')"
      @cancel-upload="emit('cancel-upload', $event)"
    />

    <div>
      <a
        :id="page.cancel.id"
        :href="page.cancel.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-ghost"
        >{{ page.cancel.label }}</a
      >
    </div>
  </CadenceFormPageFrame>
</template>
