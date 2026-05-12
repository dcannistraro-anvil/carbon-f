import { defineConfig } from "@lingui/cli";
import { formatter } from "@lingui/format-po";

export default defineConfig({
  sourceLocale: "en",
  locales: ["en", "es", "de", "it", "ja", "zh", "fr", "pl", "pt", "ru", "hi"],
  fallbackLocales: {
    default: "en"
  },
  // Drop `#: path:lineno` origins — they churn on every PR as soon as any
  // upstream code shifts and account for ~half the diff in our .po files.
  // POT-Creation-Date is stripped post-extract (see scripts/strip-po-headers.mjs).
  format: formatter({ origins: false, lineNumbers: false }),
  catalogs: [
    {
      path: "packages/locale/locales/{locale}/erp",
      include: ["apps/erp/app", "packages/react/src"],
      exclude: ["**/*.server.*", "**/*.test.*", "**/*.spec.*"]
    },
    {
      path: "packages/locale/locales/{locale}/mes",
      include: ["apps/mes/app", "packages/react/src"],
      exclude: ["**/*.server.*", "**/*.test.*", "**/*.spec.*"]
    }
  ]
});
