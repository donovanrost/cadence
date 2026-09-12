import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {},
  lint: {
    plugins: ["typescript", "unicorn", "oxc", "vue"],
    // Upstream distributions are reviewed and updated as vendored dependencies.
    ignorePatterns: ["apps/ops-console/src/vendor/**"],
    jsPlugins: [{ name: "vite-plus", specifier: "vite-plus/oxlint-plugin" }],
    rules: {
      "vite-plus/prefer-vite-plus-imports": "error",
      "typescript/no-explicit-any": "error",
      "typescript/switch-exhaustiveness-check": "error",
      "typescript/no-non-null-assertion": "error",
      "typescript/no-unsafe-assignment": "error",
      "typescript/no-unsafe-argument": "error",
      "typescript/no-unsafe-call": "error",
      "typescript/no-unsafe-member-access": "error",
      "typescript/no-unsafe-return": "error",
    },
    // Vue SFCs require the Vue compiler. The workspace check runs vue-tsc after lint.
    options: {
      typeAware: true,
      typeCheck: false,
      denyWarnings: true,
      reportUnusedDisableDirectives: "error",
    },
  },
});
