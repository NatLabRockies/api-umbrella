import { includeIgnoreFile } from "@eslint/compat";
import globals from "globals";
import pluginJs from "@eslint/js";
import importPlugin from 'eslint-plugin-import';
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const gitignorePath = path.resolve(__dirname, ".gitignore");

export default [
  includeIgnoreFile(gitignorePath),
  { languageOptions: { globals: globals.browser } },
  pluginJs.configs.recommended,
  importPlugin.flatConfigs.recommended,
  {
    languageOptions: {
      ecmaVersion: 'latest',
    },
    rules: {
      'no-console': 'error',
    }
  }
];
