// ESLint for the Cloud Functions (TypeScript, Node 22). Uses the installed
// ESLint 8 + typescript-eslint 8 in classic (.eslintrc) mode, so
// `npm run lint` (`eslint src --ext .ts`) works without a tooling upgrade.
//
// Baseline: eslint:recommended + typescript-eslint's recommended set, plus
// two type-aware promise checks that matter in Cloud Functions: a promise
// that isn't awaited can be cut off when the function returns.
module.exports = {
  root: true,
  env: {node: true, es2022: true},
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["./tsconfig.json"],
    tsconfigRootDir: __dirname,
    sourceType: "module",
  },
  plugins: ["@typescript-eslint"],
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended"],
  ignorePatterns: ["lib/", "node_modules/", ".eslintrc.js"],
  rules: {
    "@typescript-eslint/no-floating-promises": ["error", {
      // node:test's describe/test/it return promises the runner tracks
      // itself; awaiting them is not the idiom. Only these exact imports
      // are exempt — every other floating promise is still an error.
      allowForKnownSafeCalls: [
        {from: "package", package: "node:test", name: ["describe", "test", "it"]},
      ],
    }],
    "@typescript-eslint/no-misused-promises": "error",
    "eqeqeq": ["error", "always"],
  },
};
