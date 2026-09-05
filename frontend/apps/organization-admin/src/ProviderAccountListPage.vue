<script setup lang="ts">
import ProviderAccountCards from "./ProviderAccountCards.vue";

type RawAttrs = Record<string, string>;

type ElementPresentation = {
  attrs: RawAttrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type BreadcrumbItem = {
  key: string;
  separator: TextPresentation | null;
  link: TextPresentation | null;
  current: TextPresentation | null;
};

type ProviderAccountCard = InstanceType<typeof ProviderAccountCards>["$props"]["card"] & {
  __dom_id: string;
};

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: RawAttrs;
    body: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      attrs: RawAttrs;
      items: BreadcrumbItem[];
    };
    title: TextPresentation & {
      suffix: TextPresentation;
    };
    subtitle: TextPresentation;
    actions: {
      attrs: RawAttrs;
      new_account: TextPresentation & {
        icon: ElementPresentation;
      };
    };
  };
  empty_state: {
    attrs: RawAttrs;
    icon: ElementPresentation;
    title: TextPresentation;
    description: TextPresentation;
    action_container: ElementPresentation;
    action: TextPresentation & {
      icon: ElementPresentation;
    };
  } | null;
  stream: {
    attrs: RawAttrs;
    empty_marker: ElementPresentation;
  };
};

const props = defineProps<{
  presentation: Presentation;
  provider_accounts: ProviderAccountCard[];
}>();
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <nav v-bind="props.presentation.header.breadcrumbs.attrs">
            <template v-for="item in props.presentation.header.breadcrumbs.items" :key="item.key">
              <span v-if="item.separator" v-bind="item.separator.attrs">
                {{ item.separator.text }}
              </span>
              <a v-if="item.link" v-bind="item.link.attrs">{{ item.link.text }}</a>
              <span v-if="item.current" v-bind="item.current.attrs">
                {{ item.current.text }}
              </span>
            </template>
          </nav>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
            <span v-bind="props.presentation.header.title.suffix.attrs">
              {{ props.presentation.header.title.suffix.text }}
            </span>
          </h1>
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
        <div v-bind="props.presentation.header.actions.attrs">
          <a v-bind="props.presentation.header.actions.new_account.attrs">
            <span v-bind="props.presentation.header.actions.new_account.icon.attrs"></span>
            {{ props.presentation.header.actions.new_account.text }}
          </a>
        </div>
      </div>
    </header>

    <div v-if="props.presentation.empty_state" v-bind="props.presentation.empty_state.attrs">
      <span v-bind="props.presentation.empty_state.icon.attrs"></span>
      <p v-bind="props.presentation.empty_state.title.attrs">
        {{ props.presentation.empty_state.title.text }}
      </p>
      <p v-bind="props.presentation.empty_state.description.attrs">
        {{ props.presentation.empty_state.description.text }}
      </p>
      <div v-bind="props.presentation.empty_state.action_container.attrs">
        <a v-bind="props.presentation.empty_state.action.attrs">
          <span v-bind="props.presentation.empty_state.action.icon.attrs"></span>
          {{ props.presentation.empty_state.action.text }}
        </a>
      </div>
    </div>

    <div v-bind="props.presentation.stream.attrs">
      <div v-bind="props.presentation.stream.empty_marker.attrs"></div>
      <div v-for="card in props.provider_accounts" :id="card.__dom_id" :key="card.__dom_id">
        <div :id="`${card.__dom_id}-component`">
          <ProviderAccountCards :card="card" />
        </div>
      </div>
    </div>
  </div>
</template>
