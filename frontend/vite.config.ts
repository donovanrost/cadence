import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {},
  lint: {
    // Upstream distributions are reviewed and updated as vendored dependencies.
    ignorePatterns: ["apps/ops-console/src/vendor/**"],
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: { "vite-plus/prefer-vite-plus-imports": "error" },
    options: { typeAware: true, typeCheck: true },
  },
});
