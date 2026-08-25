<script setup>
import {computed} from "vue"
import CadencePopover from "./ui/reka/CadencePopover.vue"

const props = defineProps({
  presentation: {type: Object, required: true}
})

const overlayIdentity = (overlay) => {
  const identity = overlay?.root.attrs.id
  return typeof identity === "string" ? identity : null
}

const overlayPanelAttrs = (overlay) => {
  const attrs = {...(overlay?.panel.attrs || {})}
  delete attrs.hidden
  return attrs
}

const savedPresetsIdentity = computed(() =>
  overlayIdentity(props.presentation.saved_presets),
)

const savedPresetsPanelAttrs = computed(() =>
  overlayPanelAttrs(props.presentation.saved_presets),
)

const detailsIdentity = computed(() =>
  overlayIdentity(props.presentation.details),
)

const detailsPanelAttrs = computed(() =>
  overlayPanelAttrs(props.presentation.details),
)
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <span v-bind="presentation.label.attrs">{{ presentation.label.text }}</span>
    <span v-bind="presentation.summary.attrs">{{ presentation.summary.text }}</span>
    <span
      v-for="badge in presentation.badges"
      :key="badge.key"
      v-bind="badge.attrs"
    >{{ badge.text }}</span>

    <slot name="open-findings-copy"></slot>

    <form v-if="presentation.review_form" v-bind="presentation.review_form.root.attrs">
      <input v-bind="presentation.review_form.payload.attrs">
      <button v-bind="presentation.review_form.button.attrs">
        <span
          :class="[
            presentation.review_form.button.icon.name,
            presentation.review_form.button.icon.class,
          ]"
        ></span>
        {{ presentation.review_form.button.text }}
      </button>
    </form>

    <slot name="preset-copy"></slot>

    <form v-if="presentation.preset_form" v-bind="presentation.preset_form.root.attrs">
      <div v-bind="presentation.preset_form.field.wrapper.attrs">
        <label v-bind="presentation.preset_form.field.label.attrs">
          <input v-bind="presentation.preset_form.field.input.attrs">
        </label>
      </div>
      <button v-bind="presentation.preset_form.button.attrs">
        <span
          :class="[
            presentation.preset_form.button.icon.name,
            presentation.preset_form.button.icon.class,
          ]"
        ></span>
        {{ presentation.preset_form.button.text }}
      </button>
    </form>

    <CadencePopover
      v-if="presentation.saved_presets"
      :identity="savedPresetsIdentity"
      side="bottom"
      align="end"
      :side-offset="8"
      :collision-padding="16"
      v-bind="presentation.saved_presets.root.attrs"
    >
      <template #trigger="{open}">
        <button
          v-bind="presentation.saved_presets.trigger.attrs"
          :aria-expanded="String(open)"
        >
          <span :class="presentation.saved_presets.trigger.content.class">
            <span
              :class="[
                presentation.saved_presets.trigger.content.icon.name,
                presentation.saved_presets.trigger.content.icon.class,
              ]"
            ></span>
            {{ presentation.saved_presets.trigger.content.text }}
            <span :class="presentation.saved_presets.trigger.content.count.class">
              {{ presentation.saved_presets.trigger.content.count.text }}
            </span>
          </span>
        </button>
      </template>

      <template #content="{open}">
        <section
          v-bind="savedPresetsPanelAttrs"
          :hidden="!open"
        >
          <div v-bind="presentation.saved_presets.body.attrs">
            <div
              v-for="item in presentation.saved_presets.body.items"
              :key="item.key"
              v-bind="item.root.attrs"
            >
              <div v-bind="item.row.attrs">
                <div v-bind="item.copy.root.attrs">
                  <div v-bind="item.copy.name.attrs">{{ item.copy.name.text }}</div>
                  <div v-bind="item.copy.summary.attrs">{{ item.copy.summary.text }}</div>
                </div>
                <div v-bind="item.actions.attrs">
                  <button v-bind="item.actions.apply.attrs">
                    <span
                      :class="[item.actions.apply.icon.name, item.actions.apply.icon.class]"
                    ></span>
                    {{ item.actions.apply.text }}
                  </button>
                  <button v-bind="item.actions.delete.attrs">
                    <span
                      :class="[item.actions.delete.icon.name, item.actions.delete.icon.class]"
                    ></span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </section>
      </template>
    </CadencePopover>

    <CadencePopover
      v-if="presentation.details"
      :identity="detailsIdentity"
      side="bottom"
      align="end"
      :side-offset="8"
      :collision-padding="16"
      v-bind="presentation.details.root.attrs"
    >
      <template #trigger="{open}">
        <button
          v-bind="presentation.details.trigger.attrs"
          :aria-expanded="String(open)"
        >
          <span :class="presentation.details.trigger.content.class">
            <span
              :class="[
                presentation.details.trigger.content.icon.name,
                presentation.details.trigger.content.icon.class,
              ]"
            ></span>
            {{ presentation.details.trigger.content.text }}
          </span>
        </button>
      </template>

      <template #content="{open}">
        <section
          v-bind="detailsPanelAttrs"
          :hidden="!open"
        >
          <div v-bind="presentation.details.body.attrs">
            <div
              v-for="group in presentation.details.body.workflow_groups"
              :key="group.key"
              v-bind="group.root.attrs"
            >
              <div v-bind="group.heading.root.attrs">
                <span v-bind="group.heading.label.attrs">{{ group.heading.label.text }}</span>
                <span v-bind="group.heading.count.attrs">{{ group.heading.count.text }}</span>
              </div>
              <ul v-bind="group.items_root.attrs">
                <li v-for="item in group.items" :key="item.key" v-bind="item.root.attrs">
                  <a v-bind="item.link.attrs">{{ item.link.text }}</a>
                  <span v-if="item.handled" v-bind="item.handled.attrs">
                    {{ item.handled.text }}
                  </span>
                  <span v-bind="item.label.attrs">{{ item.label.text }}</span>
                </li>
              </ul>
            </div>

            <div
              v-for="group in presentation.details.body.groups"
              :key="group.key"
              v-bind="group.root.attrs"
            >
              <div v-bind="group.heading.root.attrs">
                <span v-bind="group.heading.label.attrs">{{ group.heading.label.text }}</span>
                <span v-bind="group.heading.count.attrs">{{ group.heading.count.text }}</span>
              </div>
              <ul v-bind="group.items_root.attrs">
                <li v-for="item in group.items" :key="item.key" v-bind="item.root.attrs">
                  <div v-bind="item.row.attrs">
                    <a v-bind="item.link.attrs">{{ item.link.text }}</a>
                    <span v-if="item.handled" v-bind="item.handled.attrs">
                      {{ item.handled.text }}
                    </span>
                    <span v-bind="item.label.attrs">{{ item.label.text }}</span>
                    <button v-for="action in item.actions" :key="action.key" v-bind="action.attrs">
                      <span :class="[action.icon.name, action.icon.class]"></span>
                    </button>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </section>
      </template>
    </CadencePopover>
  </div>
</template>
