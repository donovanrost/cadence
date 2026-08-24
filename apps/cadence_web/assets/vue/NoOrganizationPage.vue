<script setup lang="ts">
type RawAttrs = Record<string, string>

type ElementPresentation = {
  attrs: RawAttrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type PendingInvitationsPresentation = {
  root: ElementPresentation
  message: {
    root: ElementPresentation
    prefix: string
    count: TextPresentation
    suffix: string
  }
  link: TextPresentation
  link_icon: ElementPresentation
}

type NoOrganizationPresentation = {
  root: ElementPresentation
  heading: TextPresentation
  body: TextPresentation
  pending_invitations: PendingInvitationsPresentation | null
  sign_out: {
    form: {
      attrs: RawAttrs
      hidden_fields: ElementPresentation[]
    }
    button: TextPresentation
    icon: ElementPresentation
  }
}

defineProps<{presentation: NoOrganizationPresentation}>()
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <h1 v-bind="presentation.heading.attrs">
      {{ presentation.heading.text }}
    </h1>
    <p v-bind="presentation.body.attrs">
      {{ presentation.body.text }}
    </p>

    <div
      v-if="presentation.pending_invitations"
      v-bind="presentation.pending_invitations.root.attrs"
    >
      <p v-bind="presentation.pending_invitations.message.root.attrs">
        {{ presentation.pending_invitations.message.prefix }}
        <span v-bind="presentation.pending_invitations.message.count.attrs">
          {{ presentation.pending_invitations.message.count.text }}
        </span>
        {{ presentation.pending_invitations.message.suffix }}
      </p>
      <a v-bind="presentation.pending_invitations.link.attrs">
        {{ presentation.pending_invitations.link.text }}
        <span v-bind="presentation.pending_invitations.link_icon.attrs"></span>
      </a>
    </div>

    <form v-bind="presentation.sign_out.form.attrs">
      <input
        v-for="field in presentation.sign_out.form.hidden_fields"
        :key="field.attrs.name"
        v-bind="field.attrs"
      >
      <button v-bind="presentation.sign_out.button.attrs">
        <span v-bind="presentation.sign_out.icon.attrs"></span>
        {{ presentation.sign_out.button.text }}
      </button>
    </form>
  </div>
</template>
