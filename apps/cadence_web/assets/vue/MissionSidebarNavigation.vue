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
    <div :class="props.presentation.organization.class">
      <a
        :class="props.presentation.organization.link.class"
        v-bind="props.presentation.organization.link.attrs"
      >
        <span :class="props.presentation.organization.link.icon_class"></span>
        <span :class="props.presentation.organization.link.label_class">
          {{ props.presentation.organization.link.label }}
        </span>
      </a>
    </div>

    <div :class="props.presentation.mission.class">
      <p :class="props.presentation.mission.name_class">
        {{ props.presentation.mission.display_name }}
      </p>
      <p
        v-if="props.presentation.mission.slug_visible"
        :class="props.presentation.mission.slug_class"
      >
        {{ props.presentation.mission.slug }}
      </p>
    </div>

    <nav :class="props.presentation.navigation.class">
      <ul :class="props.presentation.navigation.list_class">
        <li
          v-for="item in props.presentation.navigation.items"
          :key="item.key"
        >
          <a
            v-if="item.kind === 'link'"
            :class="item.class"
            v-bind="item.attrs"
          >
            <span :class="item.icon_class"></span>
            <span :class="item.label_class">{{ item.label }}</span>
          </a>

          <details
            v-else
            :class="item.details_class"
            :open="item.expanded"
          >
            <summary :class="item.summary_class">
              <span :class="item.icon_class"></span>
              <span :class="item.label_class">{{ item.label }}</span>
              <span :class="item.chevron_class"></span>
            </summary>
            <ul :class="item.list_class">
              <li
                v-for="child in item.children"
                :key="child.key"
              >
                <a
                  :class="child.class"
                  v-bind="child.attrs"
                >
                  <span :class="child.icon_container_class">
                    <span :class="child.icon_class"></span>
                  </span>
                  <span :class="child.label_class">{{ child.label }}</span>
                </a>
              </li>
            </ul>
          </details>
        </li>
      </ul>
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
