/** Room Rig design tokens — mirrored from lib/theme/app_theme.dart */
export const colors = {
  bg: "#090B10",
  surface: "#11141C",
  surfaceAlt: "#181C28",
  card: "#1B2030",
  cardElevated: "#222838",
  border: "#2C3348",
  borderSubtle: "#232838",
  cyan: "#00E5FF",
  cyanDim: "#00A8B8",
  cyanGlow: "rgba(0, 229, 255, 0.2)",
  purple: "#8B7CFF",
  amber: "#FFB020",
  green: "#2EE68A",
  red: "#FF4D4D",
  orange: "#FF7A29",
  textPrimary: "#F2F4FF",
  textSecondary: "#9AA3C2",
  textMuted: "#5A6280",
  airflow: "#00E5FF",
  lighting: "#FFD666",
  ergonomics: "#5CFF7A",
  spatial: "#A78BFF",
} as const;

export const domains = [
  {
    id: "airflow",
    label: "Airflow",
    color: colors.airflow,
    blurb: "Intake, exhaust, and heat paths as coarse layout estimates — not CFD.",
  },
  {
    id: "lighting",
    label: "Lighting",
    color: colors.lighting,
    blurb: "Coverage and glare proxies from fixture placement — not radiosity.",
  },
  {
    id: "ergonomics",
    label: "Ergonomics",
    color: colors.ergonomics,
    blurb: "Reach, posture, and desk/chair relationships for day-to-day comfort.",
  },
  {
    id: "spatial",
    label: "Spatial",
    color: colors.spatial,
    blurb: "Circulation and density so the room still feels usable.",
  },
] as const;

export const githubRepo =
  process.env.NEXT_PUBLIC_GITHUB_REPO?.trim() || "yksu0/Room_Rig";

export const githubReleasesUrl = `https://github.com/${githubRepo}/releases`;
