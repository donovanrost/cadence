import { defineConfig } from "vite-plus";

export default defineConfig({
  fmt: {},
  lint: {
    plugins: ["typescript", "unicorn", "oxc", "vue"],
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
    overrides: [
      {
        // Typing plan §12 A1/A6: no narrowing assertions in the Apogee console and kit. Tests are
        // exempt: they feed deliberately invalid or partial values to runtime guards.
        files: ["apps/console/src/**/*.{ts,vue}", "packages/apogee-ui/src/**/*.{ts,vue}"],
        excludeFiles: ["**/*.test.ts"],
        rules: {
          "typescript/no-unsafe-type-assertion": "error",
          // §12 A6: a switch over a plain string must say what happens to the values it doesn't list.
          "typescript/switch-exhaustiveness-check": ["error", { requireDefaultForNonUnion: true }],
        },
      },
    ],
    // Vue SFCs require the Vue compiler. The workspace check runs vue-tsc after lint.
    options: {
      typeAware: true,
      typeCheck: false,
      denyWarnings: true,
      reportUnusedDisableDirectives: "error",
    },
  },
});
