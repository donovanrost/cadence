<script setup lang="ts">
import { reactive, watch } from "vue";
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue";
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue";
import CadencePageTitle from "./ui/components/CadencePageTitle.vue";
import CadenceField from "./ui/components/CadenceField.vue";
import CadenceFormActions from "./ui/components/CadenceFormActions.vue";
import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "./ui/components/CadenceFormSectionFrame.vue";
import CadenceFormPageFrame from "./ui/components/CadenceFormPageFrame.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Page = {
  id: string;
  heading: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

type Section = {
  id: string;
  number: string;
  title: string;
};

type Field = {
  id: string;
  name: string;
  type: "text" | "textarea";
  label: string;
  required: boolean;
  disabled: boolean;
  placeholder: string | null;
  value: string;
};

type GroundStationForm = {
  id: string;
  sections: {
    identity: Section;
    network: Section;
    metadata: Section;
  };
  fields: {
    ground_station_id: Field;
    display_name: Field;
    provider: Field;
    region: Field;
    metadata_json: Field;
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

type GroundStationValues = {
  ground_station_id: string;
  display_name: string;
  provider: string;
  region: string;
  metadata_json: string;
};

type GroundStationPayload = {
  ground_station: GroundStationValues;
};

const props = defineProps<{
  page: Page;
  mode: "new" | "edit";
  form: GroundStationForm;
}>();

const emit = defineEmits<{
  validate: [payload: GroundStationPayload];
  save: [payload: GroundStationPayload];
}>();

const formValues = (form: GroundStationForm): GroundStationValues => ({
  ground_station_id: form.fields.ground_station_id.value,
  display_name: form.fields.display_name.value,
  provider: form.fields.provider.value,
  region: form.fields.region.value,
  metadata_json: form.fields.metadata_json.value,
});

const groundStation = reactive<GroundStationValues>(formValues(props.form));

const values = (): GroundStationValues => ({
  ground_station_id: groundStation.ground_station_id,
  display_name: groundStation.display_name,
  provider: groundStation.provider,
  region: groundStation.region,
  metadata_json: groundStation.metadata_json,
});

watch(
  () => props.form,
  (serverForm) => {
    Object.assign(groundStation, formValues(serverForm));
  },
  { deep: true },
);

const validate = () => {
  const currentValues = values();
  emit("validate", { ground_station: currentValues });
};

const save = () => emit("save", { ground_station: values() });
</script>

<template>
  <CadenceFormPageFrame :id="page.id" :data-mode="mode">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <div>
          <CadenceBreadcrumbs>
            <template
              v-for="(breadcrumb, index) in page.breadcrumbs"
              :key="`${index}-${breadcrumb.label}`"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span v-if="breadcrumb.href === null" class="text-primary/90">
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
                >{{ breadcrumb.label }}</a
              >
            </template>
          </CadenceBreadcrumbs>
          <CadencePageTitle>
            {{ page.heading }}
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <CadenceFormSectionFrame :id="form.sections.identity.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.identity.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.ground_station_id.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.ground_station_id.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.ground_station_id.id"
            v-model="groundStation.ground_station_id"
            :name="form.fields.ground_station_id.name"
            :type="form.fields.ground_station_id.type"
            :placeholder="form.fields.ground_station_id.placeholder ?? undefined"
            :required="form.fields.ground_station_id.required"
            :disabled="form.fields.ground_station_id.disabled"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          :control-id="form.fields.display_name.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.display_name.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.display_name.id"
            v-model="groundStation.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :placeholder="form.fields.display_name.placeholder ?? undefined"
            :required="form.fields.display_name.required"
            :disabled="form.fields.display_name.disabled"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.network.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.network.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.network.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.provider.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.provider.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.provider.id"
            v-model="groundStation.provider"
            :name="form.fields.provider.name"
            :type="form.fields.provider.type"
            :placeholder="form.fields.provider.placeholder ?? undefined"
            :required="form.fields.provider.required"
            :disabled="form.fields.provider.disabled"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          :control-id="form.fields.region.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.region.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.region.id"
            v-model="groundStation.region"
            :name="form.fields.region.name"
            :type="form.fields.region.type"
            :placeholder="form.fields.region.placeholder ?? undefined"
            :required="form.fields.region.required"
            :disabled="form.fields.region.disabled"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.metadata.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.metadata.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.metadata.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.metadata_json.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.metadata_json.label"
          label-class="hud-label block mb-1.5"
        >
          <textarea
            :id="form.fields.metadata_json.id"
            v-model="groundStation.metadata_json"
            :name="form.fields.metadata_json.name"
            :placeholder="form.fields.metadata_json.placeholder ?? undefined"
            :required="form.fields.metadata_json.required"
            :disabled="form.fields.metadata_json.disabled"
            class="w-full textarea min-h-40 font-mono text-xs"
            @input="validate"
          ></textarea>
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button :id="form.actions.submit.id" type="submit" class="btn btn-primary">
          {{ form.actions.submit.label }}
        </button>
        <a
          :id="form.actions.cancel.id"
          :href="form.actions.cancel.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
          >{{ form.actions.cancel.label }}</a
        >
      </CadenceFormActions>
    </form>
  </CadenceFormPageFrame>
</template>
