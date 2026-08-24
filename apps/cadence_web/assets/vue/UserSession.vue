<script setup lang="ts">
import {reactive, watch} from "vue"

type Page = {
  id: string
  brand: string
  heading: string
  body: string
  access_help: string
}

type Field = {
  id: string
  name: string
  type: "email" | "password"
  label: string
  placeholder: string
  required: boolean
  autocomplete: string
  autofocus: boolean
  value: string
}

type SignInForm = {
  id: string
  action: string
  method: "post"
  csrf: {name: string; value: string}
  fields: {
    email: Field
    password: Field
  }
  submit: {id: string; label: string}
}

type UserValues = {
  email: string
  password: string
}

type ValidatePayload = {user: UserValues}

const props = defineProps<{
  page: Page
  form: SignInForm
}>()

const emit = defineEmits<{
  validate: [payload: ValidatePayload]
}>()

const formValues = (form: SignInForm): UserValues => ({
  email: form.fields.email.value,
  password: form.fields.password.value
})

const user = reactive<UserValues>(formValues(props.form))
const pendingValidations: UserValues[] = []

const values = (): UserValues => ({...user})
const acknowledges = (sent: UserValues, server: UserValues) =>
  sent.email === server.email && sent.password === server.password

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      acknowledges(sent, serverValues)
    )
    const latestPending = pendingValidations[pendingValidations.length - 1]
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !acknowledges(latestPending, serverValues)

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(user, serverValues)
  },
  {deep: true}
)

const validate = () => {
  const currentValues = values()
  pendingValidations.push(currentValues)
  emit("validate", {user: currentValues})
}

const validateField = (field: keyof UserValues, event: Event) => {
  user[field] = (event.target as HTMLInputElement).value
  validate()
}
</script>

<template>
  <div :id="page.id" class="space-y-4">
    <div class="text-center">
      <p class="text-primary tracking-[0.15em] text-sm font-semibold">
        {{ page.brand }}
      </p>
      <h1 class="mt-3 text-xl font-bold text-base-content">{{ page.heading }}</h1>
      <p class="text-xs text-base-content/70 mt-0.5">
        {{ page.body }}
      </p>
    </div>

    <form :id="form.id" :action="form.action" :method="form.method">
      <input type="hidden" :name="form.csrf.name" :value="form.csrf.value" hidden>

      <div class="fieldset mb-3">
        <label :for="form.fields.email.id">
          <span class="hud-label block mb-1.5">{{ form.fields.email.label }}</span>
          <input
            :id="form.fields.email.id"
            :value="user.email"
            :name="form.fields.email.name"
            :type="form.fields.email.type"
            :placeholder="form.fields.email.placeholder"
            :required="form.fields.email.required"
            :autocomplete="form.fields.email.autocomplete"
            :autofocus="form.fields.email.autofocus"
            class="w-full input"
            @input="validateField('email', $event)"
          >
        </label>
      </div>

      <div class="fieldset mb-3">
        <label :for="form.fields.password.id">
          <span class="hud-label block mb-1.5">{{ form.fields.password.label }}</span>
          <input
            :id="form.fields.password.id"
            :value="user.password"
            :name="form.fields.password.name"
            :type="form.fields.password.type"
            :placeholder="form.fields.password.placeholder"
            :required="form.fields.password.required"
            :autocomplete="form.fields.password.autocomplete"
            class="w-full input"
            @input="validateField('password', $event)"
          >
        </label>
      </div>

      <button
        :id="form.submit.id"
        type="submit"
        class="btn btn-primary w-full mt-2"
      >{{ form.submit.label }}</button>

      <p class="mt-3 text-center text-xs text-base-content/70">
        {{ page.access_help }}
      </p>
    </form>
  </div>
</template>
