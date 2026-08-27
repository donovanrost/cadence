<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceField from "./ui/components/CadenceField.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Page = {
  id: string
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type FormSection = {
  number: string
  title: string
}

type FormField = {
  id: string
  name: string
  type: "text" | "select"
  label: string
  required: boolean
  value: string
}

type RoutingRuleForm = {
  id: string
  sections: {
    intent: FormSection
    transport: FormSection
    policy: FormSection
  }
  fields: {
    display_name: FormField
    purpose_label: FormField
    spacecraft_id: FormField
    transport_ref: FormField
    direction: FormField
    role: FormField
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type SelectOption = {
  label: string
  value: string
}

type RoutingRuleOptions = {
  spacecraft: SelectOption[]
  transports: SelectOption[]
  directions: SelectOption[]
  roles: SelectOption[]
}

type RoutingRuleValues = {
  display_name: string
  purpose_label: string
  spacecraft_id: string
  transport_ref: string
  direction: string
  role: string
}

type RoutingRulePayload = {
  routing_rule: RoutingRuleValues
}

const props = defineProps<{
  page: Page
  form: RoutingRuleForm
  options: RoutingRuleOptions
}>()

const emit = defineEmits<{
  validate: [payload: RoutingRulePayload]
  save: [payload: RoutingRulePayload]
}>()

const formValues = (form: RoutingRuleForm): RoutingRuleValues => ({
  display_name: form.fields.display_name.value,
  purpose_label: form.fields.purpose_label.value,
  spacecraft_id: form.fields.spacecraft_id.value,
  transport_ref: form.fields.transport_ref.value,
  direction: form.fields.direction.value,
  role: form.fields.role.value
})

const values = reactive<RoutingRuleValues>(formValues(props.form))
const pendingValidations: RoutingRuleValues[] = []
const supersededValidations: RoutingRuleValues[] = []
let acceptedServerValues = formValues(props.form)

const sameValues = (left: RoutingRuleValues, right: RoutingRuleValues) =>
  left.display_name === right.display_name &&
  left.purpose_label === right.purpose_label &&
  left.spacecraft_id === right.spacecraft_id &&
  left.transport_ref === right.transport_ref &&
  left.direction === right.direction &&
  left.role === right.role

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )

    if (acknowledgedIndex >= 0) {
      supersededValidations.push(...pendingValidations.slice(0, acknowledgedIndex))

      const hasNewerTyping = acknowledgedIndex < pendingValidations.length - 1
      pendingValidations.splice(0, acknowledgedIndex + 1)
      acceptedServerValues = serverValues

      if (!hasNewerTyping && sameValues(values, serverValues)) {
        Object.assign(values, serverValues)
      }

      return
    }

    const supersededIndex = supersededValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )

    if (supersededIndex >= 0) {
      supersededValidations.splice(supersededIndex, 1)
      return
    }

    if (sameValues(serverValues, acceptedServerValues)) return

    if (pendingValidations.length === 0 && sameValues(values, acceptedServerValues)) {
      Object.assign(values, serverValues)
      acceptedServerValues = serverValues
    }
  },
  {deep: true}
)

const routingRuleValues = (): RoutingRuleValues => ({
  display_name: values.display_name,
  purpose_label: values.purpose_label,
  spacecraft_id: values.spacecraft_id,
  transport_ref: values.transport_ref,
  direction: values.direction,
  role: values.role
})

const validate = () => {
  const routingRule = routingRuleValues()
  pendingValidations.push(routingRule)
  emit("validate", {routing_rule: routingRule})
}

const save = () => emit("save", {routing_rule: routingRuleValues()})
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-2xl">
    <header class="border-b border-primary/20 pb-4">
      <div>
        <div>
          <nav
            aria-label="Breadcrumb"
            class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          >
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
              >{{ breadcrumb.label }}</a>
            </template>
          </nav>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.title }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </header>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <section id="routing-rule-intent-section" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.intent.number }}</span>
          <h2 class="hud-label">{{ form.sections.intent.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          :control-id="form.fields.display_name.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.display_name.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.display_name.id"
            v-model="values.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>

        <CadenceField
          :control-id="form.fields.purpose_label.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.purpose_label.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.purpose_label.id"
            v-model="values.purpose_label"
            :name="form.fields.purpose_label.name"
            :type="form.fields.purpose_label.type"
            :required="form.fields.purpose_label.required"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>
      </section>

      <section id="routing-rule-transport-section" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.transport.number }}</span>
          <h2 class="hud-label">{{ form.sections.transport.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          :control-id="form.fields.spacecraft_id.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.spacecraft_id.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.spacecraft_id.id"
            v-model="values.spacecraft_id"
            :name="form.fields.spacecraft_id.name"
            :required="form.fields.spacecraft_id.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.spacecraft"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.transport_ref.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.transport_ref.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.transport_ref.id"
            v-model="values.transport_ref"
            :name="form.fields.transport_ref.name"
            :required="form.fields.transport_ref.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.transports"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>
      </section>

      <section id="routing-rule-policy-section" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.policy.number }}</span>
          <h2 class="hud-label">{{ form.sections.policy.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          :control-id="form.fields.direction.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.direction.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.direction.id"
            v-model="values.direction"
            :name="form.fields.direction.name"
            :required="form.fields.direction.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.directions"
              :key="option.value"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.role.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.role.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.role.id"
            v-model="values.role"
            :name="form.fields.role.name"
            :required="form.fields.role.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.roles"
              :key="option.value"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>
      </section>

      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button :id="form.actions.submit.id" type="submit" class="btn btn-primary">
          {{ form.actions.submit.label }}
        </button>
        <a
          :id="form.actions.cancel.id"
          :href="form.actions.cancel.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
        >{{ form.actions.cancel.label }}</a>
      </div>
    </form>
  </div>
</template>
