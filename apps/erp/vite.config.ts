import { lingui } from "@lingui/vite-plugin";
import { reactRouter } from "@react-router/dev/vite";
import path from "node:path";
import { defineConfig, loadEnv, PluginOption } from "vite";
import babelMacros from "vite-plugin-babel-macros";
import tsconfigPaths from "vite-tsconfig-paths";

const repoRoot = path.resolve(__dirname, "../..");

/**
 * Node does not read `.env`; `process.env` is only inherited from the
 * parent process. Vite normally exposes `.env` via `import.meta.env`, while
 * workspace packages (e.g. `@carbon/auth`) read `process.env` — merge file-based
 * env here so SSR and `getEnv()` match your repo-root and app-local `.env*`.
 * Shell-exported variables still win (we never overwrite existing keys).
 */
function applyDotenvToProcessEnv(mode: string) {
  const fromFiles = {
    ...loadEnv(mode, repoRoot, ""),
    ...loadEnv(mode, __dirname, ""),
  };
  for (const [key, value] of Object.entries(fromFiles)) {
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

export default defineConfig(({ isSsrBuild, mode }) => {
  applyDotenvToProcessEnv(mode);

  return {
    build: {
      minify: true,
      rollupOptions: {
        onwarn(warning, defaultHandler) {
          if (warning.code === "SOURCEMAP_ERROR") {
            return;
          }

          defaultHandler(warning);
        },
        ...(isSsrBuild && { input: "./server/app.ts" }),
      },
    },
    define: {
      global: "globalThis",
    },
    ssr: {
      noExternal: [
        "react-tweet",
        "react-dropzone",
        "react-icons",
        "react-phone-number-input",
        "tailwind-merge",
      ],
    },
    server: {
      port: 3000,
      allowedHosts: [".ngrok-free.app", ".ngrok-free.dev", ".dev", ".localhost"],
      watch: {
        awaitWriteFinish: { stabilityThreshold: 250 },
      },
    },
    plugins: [
      babelMacros(),
      lingui(),
      reactRouter(),
      tsconfigPaths(),
    ] as PluginOption[],
    resolve: {
      alias: {
        "@carbon/utils": path.resolve(
          __dirname,
          "../../packages/utils/src/index.ts",
        ),
        "@carbon/form": path.resolve(
          __dirname,
          "../../packages/form/src/index.tsx",
        ),
      },
    },
  };
});
