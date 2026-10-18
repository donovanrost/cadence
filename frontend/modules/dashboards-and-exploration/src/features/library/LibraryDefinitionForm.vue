<script setup lang="ts">
defineProps<{
  mode: "create_item" | "add_version";
  selected: boolean;
  latest?: number;
  draft: { name: string; description: string; change_summary: string; widget_json: string };
  disabled: boolean;
  dirty: boolean;
  jsonError: string;
}>();
defineEmits<{ mode: [value: "create_item" | "add_version"]; save: [] }>();
</script>
<template>
  <section id="library-authoring" class="border border-base-300 p-4">
    <div class="flex flex-wrap justify-between gap-3">
      <h2 class="font-semibold">
        {{ mode === "create_item" ? "Create reusable widget" : `Add version after v${latest}` }}
      </h2>
      <span id="library-draft-state" class="font-mono text-xs text-base-content/60">{{
        dirty ? "Unsaved definition" : "Definition unchanged"
      }}</span>
    </div>
    <div class="my-4 flex flex-wrap gap-2" aria-label="Library authoring mode">
      <button
        id="library-mode-create"
        type="button"
        class="btn btn-sm"
        :aria-pressed="mode === 'create_item'"
        :disabled="disabled"
        @click="$emit('mode', 'create_item')"
      >
        New widget</button
      ><button
        id="library-mode-version"
        type="button"
        class="btn btn-sm"
        :aria-pressed="mode === 'add_version'"
        :disabled="disabled || !selected"
        @click="$emit('mode', 'add_version')"
      >
        New version
      </button>
    </div>
    <form id="library-definition-form" class="space-y-4" @submit.prevent="$emit('save')">
      <fieldset :disabled="disabled" class="space-y-4">
        <template v-if="mode === 'create_item'">
          <div>
            <label for="library-name" class="mb-1 block text-sm">Name</label
            ><input
              id="library-name"
              v-model="draft.name"
              name="name"
              required
              maxlength="120"
              class="input w-full"
            />
          </div>
          <div>
            <label for="library-description" class="mb-1 block text-sm">Description</label
            ><textarea
              id="library-description"
              v-model="draft.description"
              name="description"
              maxlength="4096"
              class="textarea w-full"
            />
          </div>
        </template>
        <div>
          <label for="library-summary" class="mb-1 block text-sm">Change summary</label
          ><input
            id="library-summary"
            v-model="draft.change_summary"
            name="change_summary"
            maxlength="4096"
            class="input w-full"
          />
        </div>
        <div>
          <label for="library-widget-json" class="mb-1 block text-sm">Widget definition JSON</label
          ><textarea
            id="library-widget-json"
            v-model="draft.widget_json"
            name="widget_json"
            required
            spellcheck="false"
            class="textarea min-h-72 w-full font-mono text-xs"
            :aria-invalid="!!jsonError"
            aria-describedby="library-json-help library-json-error"
          />
          <p id="library-json-help" class="mt-2 text-xs text-base-content/60">
            A layout-free widget definition, at most 32 KiB. The example observable must exist in
            the consuming mission. Saving a library version does not update pinned consumers.
          </p>
          <p id="library-json-error" role="status" class="mt-2 text-sm text-warning">
            {{ jsonError }}
          </p>
        </div>
        <button id="library-save-definition" type="submit" class="btn btn-sm btn-primary">
          {{ mode === "create_item" ? "Create widget" : "Save immutable version" }}
        </button>
      </fieldset>
    </form>
  </section>
</template>
