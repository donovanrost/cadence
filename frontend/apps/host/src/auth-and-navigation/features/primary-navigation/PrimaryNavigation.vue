<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceCollapsible from "@cadence/ui/CadenceCollapsible.vue";
import CadenceCollapsibleContent from "@cadence/ui/CadenceCollapsibleContent.vue";
import CadenceCollapsibleTrigger from "@cadence/ui/CadenceCollapsibleTrigger.vue";
import { navigation } from "./navigation";
import { navigateAttrs } from "../../shared/navigation";
import { readNavigationContext } from "./contracts";
const props = defineProps<{ context: unknown; mission?: boolean }>();
const collapsed = ref(false);
const model = computed(() => readNavigationContext(props.context, props.mission ?? false));
const items = computed(() => (model.value ? navigation(model.value, props.mission ?? false) : []));
</script>
<template>
  <template v-if="model">
    <label for="sidebar-drawer" aria-label="Close sidebar" class="drawer-overlay"></label>
    <aside
      data-sidebar-collapsible
      :class="[
        'sidebar-collapsible min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative',
        collapsed ? 'sidebar-collapsed' : 'sidebar-expanded',
      ]"
    >
      <div class="px-3 h-10 flex items-center border-b border-primary/20">
        <a v-bind="navigateAttrs('/')" class="flex items-center gap-2 text-xs text-primary">
          <span :class="mission ? 'hero-chevron-left h-3 w-3' : 'font-bold'">{{
            mission ? "" : "◆"
          }}</span>
          <span class="sidebar-label tracking-wide uppercase">{{
            mission ? model.organization?.display_name : "CADENCE"
          }}</span>
        </a>
      </div>
      <div v-if="mission" class="px-3 pt-4 pb-2 sidebar-expanded-only">
        <p class="text-sm font-bold truncate">{{ model.mission?.display_name }}</p>
        <p class="text-xs text-base-content/50 font-mono truncate">{{ model.mission?.slug }}</p>
      </div>
      <nav class="flex-1 overflow-y-auto py-2" aria-label="Primary navigation">
        <p v-if="!mission" class="px-3 mb-2 sidebar-expanded-only hud-label">
          {{ model.nav_context === "admin" ? "Administration" : model.organization?.display_name }}
        </p>
        <ul class="cd-side-nav">
          <li v-for="item in items" :key="item.key">
            <CadenceCollapsible
              v-if="item.kind === 'group'"
              :open="item.active"
              :client-seeded="true"
              :content-id="`mission-sidebar-${item.key}-content`"
              :seed-epoch="`${item.key}:${item.active}`"
            >
              <div class="cd-side-nav-group">
                <CadenceCollapsibleTrigger
                  ><button
                    type="button"
                    class="cd-side-nav-item"
                    :data-active-branch="item.active || undefined"
                    :aria-label="item.label"
                    :title="item.label"
                  >
                    <span :class="[item.icon, 'cd-side-nav-icon h-4 w-4']" aria-hidden="true"></span
                    ><span class="sidebar-label cd-side-nav-label">{{ item.label }}</span
                    ><span
                      class="hero-chevron-right cd-side-nav-chevron h-3 w-3"
                      aria-hidden="true"
                    ></span></button
                ></CadenceCollapsibleTrigger>
                <CadenceCollapsibleContent
                  ><ul class="cd-side-nav-children">
                    <li v-for="child in item.children" :key="child.key">
                      <a
                        v-bind="navigateAttrs(child.href)"
                        :aria-current="child.active ? 'page' : undefined"
                        class="cd-side-nav-item cd-side-nav-child"
                        ><span class="sidebar-label">{{ child.label }}</span></a
                      >
                    </li>
                  </ul></CadenceCollapsibleContent
                >
              </div>
            </CadenceCollapsible>
            <a
              v-else
              :id="item.id"
              v-bind="navigateAttrs(item.href)"
              :aria-current="item.active ? 'page' : undefined"
              class="cd-side-nav-item"
              :aria-label="item.label"
              :title="item.label"
              ><span :class="[item.icon, 'cd-side-nav-icon h-4 w-4']" aria-hidden="true"></span
              ><span class="sidebar-label">{{ item.label }}</span></a
            >
          </li>
        </ul>
      </nav>
      <form
        id="sidebar-sign-out"
        action="/session"
        method="post"
        class="border-t border-primary/20"
      >
        <input type="hidden" name="_method" value="delete" /><input
          type="hidden"
          name="_csrf_token"
          :value="model.csrf_token"
        />
        <button type="submit" class="cd-side-nav-item" aria-label="Sign out" title="Sign out">
          <span
            class="hero-arrow-right-start-on-rectangle cd-side-nav-icon h-4 w-4"
            aria-hidden="true"
          ></span
          ><span class="sidebar-label">Sign out</span>
        </button>
      </form>
      <div class="sidebar-rail-controls hidden lg:flex">
        <button
          type="button"
          title="Toggle sidebar"
          :aria-expanded="!collapsed"
          class="sidebar-toggle-btn"
          @click="collapsed = !collapsed"
        >
          <span class="hero-chevron-left h-3 w-3 toggle-chevron transition-transform"></span>
        </button>
      </div>
    </aside>
  </template>
  <nav v-else aria-label="Primary navigation" class="p-4">
    <a href="/" class="link">Cadence home</a>
    <p role="status">Navigation unavailable</p>
  </nav>
</template>
