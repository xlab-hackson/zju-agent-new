// ESLint 9 flat config。
// 关注点：TS 基础质量 + React hooks 规则 + Tailwind 类名校验
// （eslint-plugin-tailwindcss 能拦截 v3 下不存在的类名，如 p-4.5 / shadow-xs）。
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import tailwindPlugin from "eslint-plugin-tailwindcss";
import { fileURLToPath } from "node:url";

// 插件 loadConfigV3 需要绝对路径才能正确解析 tailwindcss 包
const twConfigPath = fileURLToPath(
  new URL("./apps/web/tailwind.config.js", import.meta.url),
);

export default tseslint.config(
  {
    ignores: [
      "**/dist/**",
      "**/node_modules/**",
      "**/*.d.ts",
      "apps/desktop/build/**",
      // 开发期运行时目录（日志 / PID / 一次性探针脚本），已在 .gitignore 中
      ".run/**",
    ],
  },
  // 基础 TS 规则（全仓）
  ...tseslint.configs.recommended,
  {
    rules: {
      // 项目约定：相对导入必须带 .js 后缀（tsconfig Bundler + verbatimModuleSyntax）
      // 由 TS 编译器保证，此处不重复开规则
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
  // React hooks 规则（仅前端）
  {
    files: ["apps/web/**/*.{ts,tsx}"],
    plugins: { "react-hooks": reactHooks },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
    },
  },
  // Tailwind 类名校验（仅前端；settings 指向 web 的 tailwind.config.js）
  // no-custom-classname：拦截 v3 下不存在的类名（如 p-4.5 / shadow-xs / rounded-br-xs）
  // no-contradicting-classname 已包含于插件的 recommended 语义，此处显式声明
  {
    files: ["apps/web/**/*.{ts,tsx}"],
    settings: {
      tailwindcss: {
        config: twConfigPath,
      },
    },
    plugins: { tailwindcss: tailwindPlugin },
    rules: {
      // fa-fw 是 FontAwesome 自带类（由 fontawesome-svg-core 注入），
      // input 是 Settings.tsx 内联 <style> 定义的自定义类，
      // paper-card/seal-stamp/juan-badge/ink-input/btn-ink-* 是 global.css
      // @layer components 定义的纸墨主题组件类——均非 Tailwind 原子类
      "tailwindcss/no-custom-classname": [
        "error",
        {
          whitelist: [
            "fa-fw",
            "input",
            "paper-card",
            "seal-stamp",
            "juan-badge",
            "ink-input",
            "btn-ink-primary",
            "btn-ink-outline",
            "btn-ink-danger",
          ],
        },
      ],
      "tailwindcss/classnames-order": "off",
    },
  },
  // 测试文件放宽
  {
    files: ["**/*.test.ts", "**/*.test.tsx"],
    rules: {
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
);
