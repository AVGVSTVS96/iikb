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
    "web/site/.next/**",
    "web/site/out/**",
  ],
  jsPlugins: [
    { name: "landmines-testing", specifier: "@interfere/landmines/testing" },
    { name: "landmines-style", specifier: "@interfere/landmines/style" },
    { name: "landmines-structure", specifier: "@interfere/landmines/structure" },
    { name: "landmines-types", specifier: "@interfere/landmines/types" },
  ],
  overrides: [
    {
      files: ["web/site/components/ui/**"],
      rules: { "eslint/func-style": "off", "import/consistent-type-specifier-style": "off" },
    },
    {
      files: ["web/site/**/*.js", "web/demo/**/*.js"],
      rules: {
        "typescript/no-unsafe-argument": "off",
        "typescript/no-unsafe-assignment": "off",
        "typescript/no-unsafe-call": "off",
        "typescript/no-unsafe-member-access": "off",
        "typescript/no-unsafe-return": "off",
        "typescript/strict-boolean-expressions": "off",
      },
    },
  ],
  options: { reportUnusedDisableDirectives: "error", typeAware: true },
  rules: {
    "eslint/no-redeclare": "off",
    "eslint/no-use-before-define": ["error", { functions: false, variables: false }],
    "eslint/require-await": "off",
    "eslint/sort-keys": "off",
    "unicorn/prefer-number-coercion": "off",
    "unicorn/no-await-expression-member": "off",
    "import/no-cycle": "error",
    "landmines-structure/colocated-tests": "error",
    "landmines-structure/package-exports": "error",
    "landmines-structure/test-file-names": "error",
    "landmines-style/no-comments": "error",
    "landmines-testing/no-fixed-sleep": "error",
    "landmines-testing/no-flake-masking": "error",
    "landmines-testing/no-test-doubles": "error",
    "landmines-testing/no-unsignaled-poll": "error",
    "landmines-testing/strict-msw": "error",
    "landmines-types/no-explicit-return-types": "error",
    "oxc/no-accumulating-spread": "error",
  },
});
