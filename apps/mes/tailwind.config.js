const shared = require("@carbon/config/tailwind/tailwind.config");

module.exports = {
  ...shared,
  content: [
    "./app/**/*.{ts,tsx}",
    "../../packages/{react,form,tiptap,ee}/src/**/*.{ts,tsx}",
    "!**/node_modules/**",
    "!**/__tests__/**",
    "!**/*.{test,spec,server,d}.{ts,tsx}",
  ],
};
