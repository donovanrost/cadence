<script setup lang="ts">
import CadenceToggle from "./ui/reka/CadenceToggle.vue"
import WidgetFormCallout from "./WidgetFormCallout.vue"
import WidgetFormField from "./ui/components/WidgetFormField.vue"
import type {CalloutPresentation, IconPresentation} from "./widget_form_callout"
import type {
  Attributes,
  FieldPresentation,
  TextPresentation
} from "./ui/components/widget_form_field"

type ButtonPresentation = {
  key?: string
  id?: string
  type: "button" | "submit"
  class: string
  attrs: Attributes
  text: string
  icon?: IconPresentation | null
}

type PointOptionPresentation = {
  key: string
  type: "button"
  class: string
  attrs: Attributes
  icon: IconPresentation | null
  point_id: string
  unit: TextPresentation | null
  description: TextPresentation | null
}

type ObservableOptionPresentation = {
  key: string
  type: "button"
  class: string
  attrs: Attributes
  icon: IconPresentation | null
  observable_id: string
  unit: TextPresentation | null
  name: string
  scope_badges: string[]
}

type Presentation = {
  root: {
    id: string
    class: string
    attrs: Attributes
    param: string
    params: Record<string, string>
  }
  fields: FieldPresentation[]
  point_widget: null | {
    hidden_fields: Array<{attrs: Attributes}>
    binding_fields: FieldPresentation[]
    scope_override: null | CalloutPresentation
    fixed_fields: FieldPresentation[]
    repeat: null | {
      id: string
      class: string
      guidance: {
        class: string
        icon: IconPresentation
        text: string
      }
      fields: FieldPresentation[]
    }
    point_picker: null | {
      class: string
      legend: string
      empty: null | {
        class: string
        before_link: string
        link: {
          href: string
          class: string
          text: string
          attrs: Attributes
        }
        after_link: string
      }
      selected_point: null | {
        class: string
        point: TextPresentation
        unit: TextPresentation | null
      }
      selected_points: null | {
        class: string
        attrs: Attributes
        buttons: ButtonPresentation[]
      }
      search: FieldPresentation | null
      list: null | {
        class: string
        options: PointOptionPresentation[]
        empty: boolean
        empty_class: string
        empty_text: string
      }
    }
    operational_observable_picker: null | {
      class: string
      attrs: Attributes
      legend: string
      empty: TextPresentation | null
      capability_warning: CalloutPresentation | null
      selected: null | {
        class: string
        attrs: Attributes
        buttons: ButtonPresentation[]
      }
      scope_warning: CalloutPresentation | null
      search: FieldPresentation | null
      list: null | {
        class: string
        groups: Array<{
          key: string
          attrs: Attributes
          label: TextPresentation & {attrs: Attributes}
          options: ObservableOptionPresentation[]
        }>
        empty: boolean
        empty_class: string
        empty_text: string
      }
    }
    trailing_fields: FieldPresentation[]
    chart_options: null | {
      id: string
      class: string
      label: TextPresentation
      select_grid_class: string
      select_fields: FieldPresentation[]
      checkbox_grid_class: string
      checkbox_fields: FieldPresentation[]
    }
  }
  non_point_help: TextPresentation | null
  error: TextPresentation | null
  binding_preview: null | {
    id: string
    class: string
    attrs: Attributes
    content_class: string
    icon: IconPresentation
    body_class: string
    title: TextPresentation
    message: TextPresentation
    summary: TextPresentation
  }
  actions: {
    class: string
    preview: ButtonPresentation
    submit: ButtonPresentation
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <form
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <WidgetFormField
      v-for="field in presentation.fields"
      :key="field.key"
      :field="field"
    />

    <template v-if="presentation.point_widget">
      <input
        v-for="(field, index) in presentation.point_widget.hidden_fields"
        :key="`scope-hidden-${index}`"
        v-bind="field.attrs"
      >

      <WidgetFormField
        v-for="field in presentation.point_widget.binding_fields"
        :key="field.key"
        :field="field"
      />

      <WidgetFormCallout
        v-if="presentation.point_widget.scope_override"
        :callout="presentation.point_widget.scope_override"
      />

      <WidgetFormField
        v-for="field in presentation.point_widget.fixed_fields"
        :key="field.key"
        :field="field"
      />

      <div
        v-if="presentation.point_widget.repeat"
        :id="presentation.point_widget.repeat.id"
        :class="presentation.point_widget.repeat.class"
      >
        <div :class="presentation.point_widget.repeat.guidance.class">
          <span
            :class="[
              presentation.point_widget.repeat.guidance.icon.name,
              presentation.point_widget.repeat.guidance.icon.class
            ]"
          ></span>
          <p>{{ presentation.point_widget.repeat.guidance.text }}</p>
        </div>
        <WidgetFormField
          v-for="field in presentation.point_widget.repeat.fields"
          :key="field.key"
          :field="field"
        />
      </div>

      <fieldset
        v-if="presentation.point_widget.point_picker"
        :class="presentation.point_widget.point_picker.class"
      >
        <legend class="hud-label">{{ presentation.point_widget.point_picker.legend }}</legend>

        <p
          v-if="presentation.point_widget.point_picker.empty"
          :class="presentation.point_widget.point_picker.empty.class"
        >
          {{ presentation.point_widget.point_picker.empty.before_link }}
          <a
            :href="presentation.point_widget.point_picker.empty.link.href"
            :class="presentation.point_widget.point_picker.empty.link.class"
            v-bind="presentation.point_widget.point_picker.empty.link.attrs"
          >{{ presentation.point_widget.point_picker.empty.link.text }}</a>
          {{ presentation.point_widget.point_picker.empty.after_link }}
        </p>

        <div
          v-if="presentation.point_widget.point_picker.selected_point"
          :class="presentation.point_widget.point_picker.selected_point.class"
        >
          <span :class="presentation.point_widget.point_picker.selected_point.point.class">
            {{ presentation.point_widget.point_picker.selected_point.point.text }}
          </span>
          <span
            v-if="presentation.point_widget.point_picker.selected_point.unit"
            :class="presentation.point_widget.point_picker.selected_point.unit.class"
          >{{ presentation.point_widget.point_picker.selected_point.unit.text }}</span>
        </div>

        <div
          v-if="presentation.point_widget.point_picker.selected_points"
          :class="presentation.point_widget.point_picker.selected_points.class"
          v-bind="presentation.point_widget.point_picker.selected_points.attrs"
        >
          <button
            v-for="button in presentation.point_widget.point_picker.selected_points.buttons"
            :key="button.key"
            :type="button.type"
            :class="button.class"
            v-bind="button.attrs"
          >
            {{ button.text }}
            <span v-if="button.icon" :class="[button.icon.name, button.icon.class]"></span>
          </button>
        </div>

        <WidgetFormField
          v-if="presentation.point_widget.point_picker.search"
          :field="presentation.point_widget.point_picker.search"
        />

        <ul
          v-if="presentation.point_widget.point_picker.list"
          :class="presentation.point_widget.point_picker.list.class"
        >
          <li
            v-for="option in presentation.point_widget.point_picker.list.options"
            :key="option.key"
          >
            <CadenceToggle
              :pressed="option.attrs['aria-pressed'] === 'true'"
            >
              <button
                :type="option.type"
                :class="option.class"
                v-bind="option.attrs"
              >
                <span v-if="option.icon" :class="[option.icon.name, option.icon.class]"></span>
                <span class="font-mono">{{ option.point_id }}</span>
                <span v-if="option.unit" :class="option.unit.class">{{ option.unit.text }}</span>
                <span v-if="option.description" :class="option.description.class">
                  {{ option.description.text }}
                </span>
              </button>
            </CadenceToggle>
          </li>
          <li
            v-if="presentation.point_widget.point_picker.list.empty"
            :class="presentation.point_widget.point_picker.list.empty_class"
          >
            {{ presentation.point_widget.point_picker.list.empty_text }}
          </li>
        </ul>
      </fieldset>

      <fieldset
        v-if="presentation.point_widget.operational_observable_picker"
        :class="presentation.point_widget.operational_observable_picker.class"
        v-bind="presentation.point_widget.operational_observable_picker.attrs"
      >
        <legend class="hud-label">
          {{ presentation.point_widget.operational_observable_picker.legend }}
        </legend>

        <p
          v-if="presentation.point_widget.operational_observable_picker.empty"
          :class="presentation.point_widget.operational_observable_picker.empty.class"
        >
          {{ presentation.point_widget.operational_observable_picker.empty.text }}
        </p>

        <WidgetFormCallout
          v-if="presentation.point_widget.operational_observable_picker.capability_warning"
          :callout="presentation.point_widget.operational_observable_picker.capability_warning"
        />

        <div
          v-if="presentation.point_widget.operational_observable_picker.selected"
          :class="presentation.point_widget.operational_observable_picker.selected.class"
          v-bind="presentation.point_widget.operational_observable_picker.selected.attrs"
        >
          <button
            v-for="button in presentation.point_widget.operational_observable_picker.selected.buttons"
            :key="button.key"
            :type="button.type"
            :class="button.class"
            v-bind="button.attrs"
          >
            {{ button.text }}
            <span v-if="button.icon" :class="[button.icon.name, button.icon.class]"></span>
          </button>
        </div>

        <WidgetFormCallout
          v-if="presentation.point_widget.operational_observable_picker.scope_warning"
          :callout="presentation.point_widget.operational_observable_picker.scope_warning"
        />

        <WidgetFormField
          v-if="presentation.point_widget.operational_observable_picker.search"
          :field="presentation.point_widget.operational_observable_picker.search"
        />

        <ul
          v-if="presentation.point_widget.operational_observable_picker.list"
          :class="presentation.point_widget.operational_observable_picker.list.class"
        >
          <li
            v-for="group in presentation.point_widget.operational_observable_picker.list.groups"
            :key="group.key"
            v-bind="group.attrs"
          >
            <div :class="group.label.class" v-bind="group.label.attrs">
              {{ group.label.text }}
            </div>
            <ul class="space-y-1">
              <li v-for="option in group.options" :key="option.key">
                <CadenceToggle
                  :pressed="option.attrs['aria-pressed'] === 'true'"
                  :disabled="option.attrs.disabled !== undefined"
                >
                  <button
                    :type="option.type"
                    :class="option.class"
                    v-bind="option.attrs"
                  >
                    <span v-if="option.icon" :class="[option.icon.name, option.icon.class]"></span>
                    <span class="font-mono">{{ option.observable_id }}</span>
                    <span v-if="option.unit" :class="option.unit.class">{{ option.unit.text }}</span>
                    <span class="ml-2 text-base-content/60">{{ option.name }}</span>
                    <span class="ml-auto flex flex-wrap justify-end gap-1">
                      <span
                        v-for="scope in option.scope_badges"
                        :key="scope"
                        class="badge badge-ghost badge-xs whitespace-nowrap"
                      >{{ scope }}</span>
                    </span>
                  </button>
                </CadenceToggle>
              </li>
            </ul>
          </li>
          <li
            v-if="presentation.point_widget.operational_observable_picker.list.empty"
            :class="presentation.point_widget.operational_observable_picker.list.empty_class"
          >
            {{ presentation.point_widget.operational_observable_picker.list.empty_text }}
          </li>
        </ul>
      </fieldset>

      <WidgetFormField
        v-for="field in presentation.point_widget.trailing_fields"
        :key="field.key"
        :field="field"
      />

      <div
        v-if="presentation.point_widget.chart_options"
        :id="presentation.point_widget.chart_options.id"
        :class="presentation.point_widget.chart_options.class"
      >
        <p :class="presentation.point_widget.chart_options.label.class">
          {{ presentation.point_widget.chart_options.label.text }}
        </p>
        <div :class="presentation.point_widget.chart_options.select_grid_class">
          <WidgetFormField
            v-for="field in presentation.point_widget.chart_options.select_fields"
            :key="field.key"
            :field="field"
          />
        </div>
        <div :class="presentation.point_widget.chart_options.checkbox_grid_class">
          <WidgetFormField
            v-for="field in presentation.point_widget.chart_options.checkbox_fields"
            :key="field.key"
            :field="field"
          />
        </div>
      </div>
    </template>

    <p v-if="presentation.non_point_help" :class="presentation.non_point_help.class">
      {{ presentation.non_point_help.text }}
    </p>

    <p v-if="presentation.error" :class="presentation.error.class">
      {{ presentation.error.text }}
    </p>

    <div
      v-if="presentation.binding_preview"
      :id="presentation.binding_preview.id"
      :class="presentation.binding_preview.class"
      v-bind="presentation.binding_preview.attrs"
    >
      <div :class="presentation.binding_preview.content_class">
        <span
          :class="[
            presentation.binding_preview.icon.name,
            presentation.binding_preview.icon.class
          ]"
        ></span>
        <div :class="presentation.binding_preview.body_class">
          <p :class="presentation.binding_preview.title.class">
            {{ presentation.binding_preview.title.text }}
          </p>
          <p :class="presentation.binding_preview.message.class">
            {{ presentation.binding_preview.message.text }}
          </p>
          <p :class="presentation.binding_preview.summary.class">
            {{ presentation.binding_preview.summary.text }}
          </p>
        </div>
      </div>
    </div>

    <div :class="presentation.actions.class">
      <button
        :id="presentation.actions.preview.id"
        :type="presentation.actions.preview.type"
        :class="presentation.actions.preview.class"
        v-bind="presentation.actions.preview.attrs"
      >
        <span
          v-if="presentation.actions.preview.icon"
          :class="[
            presentation.actions.preview.icon.name,
            presentation.actions.preview.icon.class
          ]"
        ></span>
        {{ presentation.actions.preview.text }}
      </button>
      <button
        :id="presentation.actions.submit.id"
        :type="presentation.actions.submit.type"
        :class="presentation.actions.submit.class"
        v-bind="presentation.actions.submit.attrs"
      >
        {{ presentation.actions.submit.text }}
      </button>
    </div>
  </form>
</template>
