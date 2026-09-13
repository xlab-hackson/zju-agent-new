/** @type {import('tailwindcss').Config} */
export default {
  content: ["./*.html", "./src/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        zju: {
          primary: "#003f88",
          light: "#2b6cb0",
        },
        /* === 求是书院 · 纸墨学术风设计令牌 === */
        paper: {
          DEFAULT: "#f3ecdc", // 暖白纸底
          card: "#fdfaf2", // 卡片纸色
          deep: "#ece2c8", // 深一档纸色（表头/底栏）
        },
        ink: {
          DEFAULT: "#22304e", // 墨蓝正文
          deep: "#0e1c38", // 深墨（大标题）
          soft: "#5b6884", // 次级正文
          faint: "#8b93a7", // 弱化说明
        },
        qiushi: {
          DEFAULT: "#003f88", // 求是蓝
          dark: "#12233f", // 侧栏深墨蓝
          deeper: "#0a1428",
        },
        gold: {
          DEFAULT: "#b08d3e", // 金色点缀
          bright: "#c9a227",
          faint: "#e4d5ac",
        },
        seal: {
          DEFAULT: "#b03a2e", // 印章朱红
          light: "#d9705f",
        },
        bamboo: "#2e7d32", // 竹青（进行中/成功）
      },
      fontFamily: {
        serif: [
          '"Noto Serif SC Variable"',
          '"Noto Serif SC"',
          '"Songti SC"',
          '"STSong"',
          "SimSun",
          "serif",
        ],
        brush: ['"Ma Shan Zheng"', '"Noto Serif SC Variable"', "serif"],
        mono: ['"JetBrains Mono Variable"', '"JetBrains Mono"', "Consolas", "monospace"],
      },
      boxShadow: {
        paper: "2px 3px 0 rgba(14,28,56,.05), 0 10px 24px -18px rgba(14,28,56,.35)",
        "paper-hover":
          "3px 6px 0 rgba(14,28,56,.08), 0 16px 30px -18px rgba(14,28,56,.4)",
        seal: "2px 2px 0 rgba(14,28,56,.22)",
      },
      borderRadius: {
        paper: "3px",
      },
    },
  },
  plugins: [],
};
