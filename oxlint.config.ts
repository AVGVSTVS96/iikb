import { defineConfig } from "oxlint";
import antiSlop from "ultracite/oxlint/anti-slop";
import core from "ultracite/oxlint/core";

export default defineConfig({
  extends: [core, antiSlop],
  ignorePatterns: [
    ...(core.ignorePatterns ?? []),
    ".claude/**",
    "web/dist/**",
    "web/.build/**",
    "web/site/**",
  ],
  jsPlugins: [{ name: "no-comments", specifier: "./tools/oxlint/no-comments.ts" }],
  options: { reportUnusedDisableDirectives: "error", typeAware: true },
  rules: {
    "eslint/no-redeclare": "off",
    "eslint/no-use-before-define": ["error", { functions: false, variables: false }],
    "eslint/require-await": "off",
    "eslint/sort-keys": "off",
    "unicorn/no-await-expression-member": "off",
    "import/no-cycle": "error",
    "no-comments/no-comments": "error",
    "oxc/no-accumulating-spread": "error",
  },
});
