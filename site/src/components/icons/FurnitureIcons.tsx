import type { SVGProps } from "react";

type IconProps = SVGProps<SVGSVGElement> & { title?: string };

export function DeskIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden={!props.title} {...props}>
      {props.title ? <title>{props.title}</title> : null}
      <rect x="1" y="10" width="62" height="44" rx="2" stroke="currentColor" strokeWidth="2.5" fill="currentColor" fillOpacity="0.22" />
      <rect x="4" y="13" width="56" height="38" rx="1" stroke="currentColor" strokeWidth="1.5" />
      <circle cx="8" cy="16" r="2.2" fill="currentColor" />
      <circle cx="56" cy="16" r="2.2" fill="currentColor" />
      <circle cx="8" cy="48" r="2.2" fill="currentColor" />
      <circle cx="56" cy="48" r="2.2" fill="currentColor" />
    </svg>
  );
}

export function MonitorIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden={!props.title} {...props}>
      {props.title ? <title>{props.title}</title> : null}
      <rect x="6" y="8" width="52" height="36" rx="3" stroke="currentColor" strokeWidth="2.5" fill="currentColor" fillOpacity="0.18" />
      <rect x="10" y="12" width="44" height="28" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
      <path d="M24 48h16" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M32 44v4" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}

export function FanIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden={!props.title} {...props}>
      {props.title ? <title>{props.title}</title> : null}
      <circle cx="32" cy="32" r="6" fill="currentColor" />
      <path d="M32 8c6 8 6 16 0 24 6-8 14-8 24 0-8-6-16-6-24 0 8 6 8 14 0 24-6-8-14-8-24 0 8 6 16 6 24 0-8-6-8-14 0-24z" stroke="currentColor" strokeWidth="2.2" fill="currentColor" fillOpacity="0.15" />
    </svg>
  );
}

export function LampIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden={!props.title} {...props}>
      {props.title ? <title>{props.title}</title> : null}
      <path d="M20 28h24l-4-14H24l-4 14z" stroke="currentColor" strokeWidth="2.5" fill="currentColor" fillOpacity="0.2" />
      <path d="M32 28v22" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M22 54h20" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      <circle cx="32" cy="18" r="3" fill="currentColor" />
    </svg>
  );
}

export function ChairIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 64 64" fill="none" aria-hidden={!props.title} {...props}>
      {props.title ? <title>{props.title}</title> : null}
      <rect x="18" y="8" width="28" height="22" rx="4" stroke="currentColor" strokeWidth="2.5" fill="currentColor" fillOpacity="0.18" />
      <rect x="14" y="30" width="36" height="10" rx="3" stroke="currentColor" strokeWidth="2.5" fill="currentColor" fillOpacity="0.22" />
      <path d="M22 40v14M42 40v14M18 54h28" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}
