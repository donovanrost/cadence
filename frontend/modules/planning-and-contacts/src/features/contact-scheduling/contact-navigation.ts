import { inject, type Component, type InjectionKey } from "vue";

/** The host supplies navigation; the feature keeps usable native links outside it. */
export type ContactNavigation = {
  link: Component;
  navigate(href: string): void;
};
export const contactNavigationKey: InjectionKey<ContactNavigation> = Symbol("contact-navigation");

export function useContactQueryNavigation() {
  const navigation = inject(contactNavigationKey, undefined);
  return (event: Event) => {
    if (!navigation || !(event.currentTarget instanceof HTMLFormElement)) return;
    const form = event.currentTarget;
    const target = new URL(form.action, window.location.origin);
    const query = new URLSearchParams();
    for (const [key, value] of new FormData(form)) {
      if (typeof value === "string") query.append(key, value);
    }
    target.search = query.toString();
    event.preventDefault();
    navigation.navigate(target.pathname + target.search);
  };
}
