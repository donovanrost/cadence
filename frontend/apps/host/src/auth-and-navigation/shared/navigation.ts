export const navigateAttrs = (href: string) => ({
  href,
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
});
export const canAdminister = (context: { capabilities: readonly string[] }) =>
  context.capabilities.some((capability) =>
    ["organization_admin", "platform_admin"].includes(capability),
  );
