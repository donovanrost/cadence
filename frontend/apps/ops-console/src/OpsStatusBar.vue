<script setup lang="ts">
import UtcClock from "./UtcClock.vue";
import NotificationsBell from "./NotificationsBell.vue";
import UserMenu from "./UserMenu.vue";

type Attributes = Record<string, string>;
type TextValue = string | number | boolean | null;

type TextPresentation = {
  class: string;
  text: TextValue;
};

type PosturePresentation =
  | {
      kind: "critical" | "warning";
      id: string;
      root_class: string;
      class: string;
      dot_class: string;
      count: TextPresentation;
      label: TextPresentation;
    }
  | {
      kind: "nominal";
      id: string;
      root_class: string;
      class: string;
      dot_class: string;
      label: string;
    }
  | {
      kind: "unavailable";
      id: string;
      root_class: string;
      class: string;
      label: string;
    };

type NotificationsBellPresentation = InstanceType<
  typeof NotificationsBell
>["$props"]["presentation"];
type UserMenuPresentation = InstanceType<typeof UserMenu>["$props"]["presentation"];

type NotificationsBellComposition = {
  component: "NotificationsBell";
  id: string;
  class: string;
  presentation: NotificationsBellPresentation;
};

type UserMenuComposition = {
  component: "UserMenu";
  id: string;
  class: string;
  presentation: UserMenuPresentation;
};

type ConnectionIndicator = {
  id: string;
  class: string;
  title: string;
  attrs: Attributes;
};

type Presentation = {
  header: { class: string };
  mission: {
    class: string;
    attrs: Attributes;
    icon_class: string;
    name: TextPresentation;
    slug: TextPresentation;
  };
  posture: PosturePresentation;
  clock: { component: "UtcClock"; id: string; class: string };
  connection: { ok: ConnectionIndicator; lost: ConnectionIndicator };
  account: null | {
    notifications_bell: NotificationsBellComposition | null;
    user_menu: UserMenuComposition | null;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <header :class="presentation.header.class">
    <a :class="presentation.mission.class" v-bind="presentation.mission.attrs">
      <span :class="presentation.mission.icon_class"></span>
      <span :class="presentation.mission.name.class">{{ presentation.mission.name.text }}</span>
      <span :class="presentation.mission.slug.class">{{ presentation.mission.slug.text }}</span>
    </a>

    <div :id="presentation.posture.id" :class="presentation.posture.root_class">
      <span
        v-if="presentation.posture.kind === 'critical' || presentation.posture.kind === 'warning'"
        :class="presentation.posture.class"
      >
        <span :class="presentation.posture.dot_class"></span>
        <span :class="presentation.posture.count.class">{{ presentation.posture.count.text }}</span>
        <span :class="presentation.posture.label.class">{{ presentation.posture.label.text }}</span>
      </span>
      <span v-else-if="presentation.posture.kind === 'nominal'" :class="presentation.posture.class">
        <span :class="presentation.posture.dot_class"></span>
        {{ presentation.posture.label }}
      </span>
      <span v-else :class="presentation.posture.class">
        {{ presentation.posture.label }}
      </span>
    </div>

    <div :id="presentation.clock.id" :class="presentation.clock.class">
      <UtcClock />
    </div>
    <span
      :id="presentation.connection.ok.id"
      :class="presentation.connection.ok.class"
      :title="presentation.connection.ok.title"
      v-bind="presentation.connection.ok.attrs"
    ></span>
    <span
      :id="presentation.connection.lost.id"
      :class="presentation.connection.lost.class"
      :title="presentation.connection.lost.title"
      v-bind="presentation.connection.lost.attrs"
    ></span>

    <div
      v-if="presentation.account?.notifications_bell"
      :id="presentation.account.notifications_bell.id"
      :class="presentation.account.notifications_bell.class"
    >
      <NotificationsBell :presentation="presentation.account.notifications_bell.presentation" />
    </div>
    <div
      v-if="presentation.account?.user_menu"
      :id="presentation.account.user_menu.id"
      :class="presentation.account.user_menu.class"
    >
      <UserMenu :presentation="presentation.account.user_menu.presentation" />
    </div>
  </header>
</template>
