<script setup>
import {ref} from "vue"

const props = defineProps({
  presentation: {type: Object, required: true},
})

const collapsed = ref(false)

const sidebarClass = () =>
  collapsed.value
    ? props.presentation.root.collapsed_class
    : props.presentation.root.expanded_class

const toggleCollapsed = () => {
  collapsed.value = !collapsed.value
}
</script>

<template>
  <label
    :class="props.presentation.overlay.class"
    v-bind="props.presentation.overlay.attrs"
  ></label>

  <div
    :class="sidebarClass()"
    v-bind="props.presentation.root.attrs"
  >
    <div :class="props.presentation.header.class">
      <a
        :class="props.presentation.header.link.class"
        v-bind="props.presentation.header.link.attrs"
      >
        <span :class="props.presentation.header.link.icon_class">
          {{ props.presentation.header.link.icon_text }}
        </span>
        <span :class="props.presentation.header.link.label_class">
          {{ props.presentation.header.link.label }}
        </span>
      </a>
    </div>

    <nav :class="props.presentation.navigation.class">
      <template v-if="props.presentation.navigation.section">
        <div :class="props.presentation.navigation.section.class">
          <span :class="props.presentation.navigation.section.label_class">
            {{ props.presentation.navigation.section.label }}
          </span>
        </div>
        <ul :class="props.presentation.navigation.list_class">
          <li
            v-for="item in props.presentation.navigation.items"
            :key="item.key"
          >
            <a
              :class="item.class"
              v-bind="item.attrs"
            >
              <span :class="item.icon_class"></span>
              <span :class="item.label_class">{{ item.label }}</span>
            </a>
          </li>
        </ul>
      </template>
    </nav>

    <div :class="props.presentation.sign_out.class">
      <form v-bind="props.presentation.sign_out.form.attrs">
        <input
          v-for="field in props.presentation.sign_out.form.hidden_fields"
          :key="field.key"
          v-bind="field.attrs"
        >
        <button
          :class="props.presentation.sign_out.form.button.class"
          v-bind="props.presentation.sign_out.form.button.attrs"
        >
          <span :class="props.presentation.sign_out.form.button.icon_class"></span>
          <span :class="props.presentation.sign_out.form.button.label_class">
            {{ props.presentation.sign_out.form.button.label }}
          </span>
        </button>
      </form>
    </div>

    <button
      :class="props.presentation.collapse.class"
      v-bind="props.presentation.collapse.attrs"
      @click="toggleCollapsed"
    >
      <span :class="props.presentation.collapse.icon_class"></span>
    </button>
  </div>
</template>
