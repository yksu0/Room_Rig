import type { Metadata } from "next";
import { Outfit } from "next/font/google";
import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import "./globals.css";

const outfit = Outfit({
  subsets: ["latin"],
  variable: "--font-outfit",
  weight: ["400", "500", "600", "700", "800"],
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "Room Rig",
    template: "%s · Room Rig",
  },
  description:
    "Treat your room like a PC build. Layout → score → optimize. The Android app for Hub, Room, Scan, and Benchmark.",
  metadataBase: new URL("https://roomrig.vercel.app"),
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "https://roomrig.vercel.app",
    siteName: "Room Rig",
    title: "Room Rig",
    description:
      "Treat your room like a PC build. Layout → score → optimize. The Android app for Hub, Room, Scan, and Benchmark.",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
    },
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={outfit.variable}>
      <body className="page-wash font-outfit antialiased">
        <SiteNav />
        <main className="min-h-[70vh]">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
