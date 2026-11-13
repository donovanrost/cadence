/**
 * A route param read as text where the route isn't one known name: shell code above every route,
 * a screen registered under several routes, or a redirect. "" when the param is absent. Screens on
 * one route use `useRoute("name").params` instead (typed routes, typing audit Fix 4).
 */
export function paramText(params: object, key: string): string {
  const value: unknown = Reflect.get(params, key);
  return typeof value === "string" ? value : "";
}
