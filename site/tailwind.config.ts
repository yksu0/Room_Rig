import type { Config } from "tailwindcss";

export default {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        bg: "#090B10",
        surface: "#11141C",
        "surface-alt": "#181C28",
        card: "#1B2030",
        "card-elevated": "#222838",
        border: "#2C3348",
        "border-subtle": "#232838",
        cyan: "#00E5FF",
        "cyan-dim": "#00A8B8",
        purple: "#8B7CFF",
        amber: "#FFB020",
        green: "#2EE68A",
        red: "#FF4D4D",
        orange: "#FF7A29",
        ink: "#F2F4FF",
        "ink-secondary": "#9AA3C2",
        "ink-muted": "#5A6280",
        airflow: "#00E5FF",
        lighting: "#FFD666",
        ergonomics: "#5CFF7A",
        spatial: "#A78BFF",
      },
      fontFamily: {
        outfit: ["var(--font-outfit)", "system-ui", "sans-serif"],
      },
      borderRadius: {
        rr: "14px",
        "rr-lg": "18px",
        "rr-xl": "22px",
      },
      boxShadow: {
        glow: "0 0 16px rgba(0, 229, 255, 0.22)",
        "glow-strong": "0 0 24px rgba(0, 229, 255, 0.35)",
      },
      backgroundImage: {
        "accent-grad": "linear-gradient(135deg, #00E5FF 0%, #00B4D8 100%)",
        "card-grad": "linear-gradient(135deg, #1E2436 0%, #151925 100%)",
        "hero-wash": "linear-gradient(180deg, #0E1522 0%, #090B10 100%)",
      },
    },
  },
  plugins: [],
} satisfies Config;
