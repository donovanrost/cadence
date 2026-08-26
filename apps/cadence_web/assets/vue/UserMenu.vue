<script setup lang="ts">
import AccountDropdownMenu from "./ui/reka/AccountDropdownMenu.vue"
import CadenceMenuItem from "./ui/reka/CadenceMenuItem.vue"

type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type HiddenField = {attrs: Attributes}

type FormPresentation = {
  attrs: Attributes
  hidden_fields: HiddenField[]
  item_class?: string | null
  item_attrs?: Attributes
  button: {
    class: string
    attrs: Attributes
    icon_class?: string
    label: string
    label_class?: string
  }
}

type OrganizationPresentation = {
  element: "div"
  class: string
  attrs: Attributes
  label: TextPresentation
  current: TextPresentation
  switcher: null | {
    class: string
    summary: {
      class: string
      label_class: string
      label: string
      icon_class: string
    }
    list_class: string
    organizations: Array<{
      key: string
      item_attrs: Attributes
      form: FormPresentation
      label: string
    }>
  }
}

type MenuAction = {
  item_class: string
  item_attrs: Attributes
  class: string
  attrs: Attributes
  icon_class: string
  label: string
}

type Presentation = {
  root: {class: string}
  trigger: {
    class: string
    attrs: Attributes
    label: TextPresentation
    icon_class: string
  }
  menu: {
    id: string
    class: string
    attrs: Attributes
    identity: {
      element: "div"
      class: string
      attrs: Attributes
      label: TextPresentation
      email: TextPresentation | null
    }
    organization: OrganizationPresentation | null
    admin_action: MenuAction | null
    leave_admin_mode: FormPresentation | null
    sign_out: FormPresentation
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <AccountDropdownMenu :class="presentation.root.class">
    <template #trigger="{open}">
      <button
        :class="presentation.trigger.class"
        v-bind="presentation.trigger.attrs"
        :aria-expanded="String(open)"
      >
        <span :class="presentation.trigger.label.class">{{ presentation.trigger.label.text }}</span>
        <span :class="presentation.trigger.icon_class"></span>
      </button>
    </template>

    <template #content="{open, onItemSelect}">
      <div
        :id="presentation.menu.id"
        :class="presentation.menu.class"
        v-bind="presentation.menu.attrs"
      >
      <component
        :is="presentation.menu.identity.element"
        :class="presentation.menu.identity.class"
        v-bind="presentation.menu.identity.attrs"
      >
        <p :class="presentation.menu.identity.label.class">
          {{ presentation.menu.identity.label.text }}
        </p>
        <p
          v-if="presentation.menu.identity.email"
          :class="presentation.menu.identity.email.class"
        >{{ presentation.menu.identity.email.text }}</p>
      </component>

      <component
        v-if="presentation.menu.organization"
        :is="presentation.menu.organization.element"
        :class="presentation.menu.organization.class"
        v-bind="presentation.menu.organization.attrs"
      >
        <span :class="presentation.menu.organization.label.class">
          {{ presentation.menu.organization.label.text }}
        </span>
        <details
          v-if="presentation.menu.organization.switcher"
          :class="presentation.menu.organization.switcher.class"
        >
          <summary :class="presentation.menu.organization.switcher.summary.class">
            <span :class="presentation.menu.organization.switcher.summary.label_class">
              {{ presentation.menu.organization.switcher.summary.label }}
            </span>
            <span :class="presentation.menu.organization.switcher.summary.icon_class"></span>
          </summary>
          <ul :class="presentation.menu.organization.switcher.list_class">
            <li
              v-for="organization in presentation.menu.organization.switcher.organizations"
              :key="organization.key"
              v-bind="organization.item_attrs"
            >
              <form v-bind="organization.form.attrs">
                <input
                  v-for="(field, index) in organization.form.hidden_fields"
                  :key="index"
                  v-bind="field.attrs"
                >
                <CadenceMenuItem
                  :active="open"
                  @select="onItemSelect"
                >
                  <button
                    :class="organization.form.button.class"
                    v-bind="organization.form.button.attrs"
                  >
                    <span :class="organization.form.button.label_class">{{ organization.label }}</span>
                  </button>
                </CadenceMenuItem>
              </form>
            </li>
          </ul>
        </details>
        <p v-else :class="presentation.menu.organization.current.class">
          {{ presentation.menu.organization.current.text }}
        </p>
      </component>

      <li
        v-if="presentation.menu.admin_action"
        :class="presentation.menu.admin_action.item_class"
        v-bind="presentation.menu.admin_action.item_attrs"
      >
        <CadenceMenuItem
          :active="open"
          @select="onItemSelect"
        >
          <a
            :class="presentation.menu.admin_action.class"
            v-bind="presentation.menu.admin_action.attrs"
          >
            <span :class="presentation.menu.admin_action.icon_class"></span>
            {{ presentation.menu.admin_action.label }}
          </a>
        </CadenceMenuItem>
      </li>

      <li
        v-if="presentation.menu.leave_admin_mode"
        :class="presentation.menu.leave_admin_mode.item_class"
        v-bind="presentation.menu.leave_admin_mode.item_attrs"
      >
        <form v-bind="presentation.menu.leave_admin_mode.attrs">
          <input
            v-for="(field, index) in presentation.menu.leave_admin_mode.hidden_fields"
            :key="index"
            v-bind="field.attrs"
          >
          <CadenceMenuItem
            :active="open"
            @select="onItemSelect"
          >
            <button
              :class="presentation.menu.leave_admin_mode.button.class"
              v-bind="presentation.menu.leave_admin_mode.button.attrs"
            >
              <span :class="presentation.menu.leave_admin_mode.button.icon_class"></span>
              {{ presentation.menu.leave_admin_mode.button.label }}
            </button>
          </CadenceMenuItem>
        </form>
      </li>

      <li
        :class="presentation.menu.sign_out.item_class"
        v-bind="presentation.menu.sign_out.item_attrs"
      >
        <form v-bind="presentation.menu.sign_out.attrs">
          <input
            v-for="(field, index) in presentation.menu.sign_out.hidden_fields"
            :key="index"
            v-bind="field.attrs"
          >
          <CadenceMenuItem
            :active="open"
            @select="onItemSelect"
          >
            <button
              :class="presentation.menu.sign_out.button.class"
              v-bind="presentation.menu.sign_out.button.attrs"
            >
              <span :class="presentation.menu.sign_out.button.icon_class"></span>
              {{ presentation.menu.sign_out.button.label }}
            </button>
          </CadenceMenuItem>
        </form>
      </li>
      </div>
    </template>
  </AccountDropdownMenu>
</template>
