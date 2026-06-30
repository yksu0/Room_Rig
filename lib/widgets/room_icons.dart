// lib/widgets/room_icons.dart
// All app icons as inline SVG strings — no emojis anywhere.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class RoomSvg {
  RoomSvg._();

  // ─── Furniture ───────────────────────────────────────────────────────────
  static const String bed = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="14" width="20" height="6" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <rect x="4" y="9" width="7" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
  <rect x="13" y="9" width="7" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
  <line x1="2" y1="14" x2="2" y2="20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="22" y1="14" x2="22" y2="20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <rect x="2" y="12" width="20" height="2" rx="0.5" fill="currentColor" opacity="0.3"/>
</svg>''';

  static const String desk = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="8" width="20" height="3" rx="1" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="11" x2="5" y2="19" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="19" y1="11" x2="19" y2="19" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <rect x="6" y="4" width="8" height="5" rx="0.8" stroke="currentColor" stroke-width="1.3"/>
  <rect x="15" y="5" width="4" height="3" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
  <line x1="7" y1="6" x2="13" y2="6" stroke="currentColor" stroke-width="0.8" stroke-linecap="round" opacity="0.6"/>
  <line x1="7" y1="7.5" x2="11" y2="7.5" stroke="currentColor" stroke-width="0.8" stroke-linecap="round" opacity="0.6"/>
</svg>''';

  static const String chair = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7 4 L7 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M7 4 Q7 2 9 2 L15 2 Q17 2 17 4 L17 8" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <rect x="5" y="11" width="14" height="3" rx="1.5" stroke="currentColor" stroke-width="1.4"/>
  <line x1="8" y1="14" x2="7" y2="20" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="16" y1="14" x2="17" y2="20" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="7" y1="20" x2="5" y2="20" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="17" y1="20" x2="19" y2="20" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
</svg>''';

  static const String pcTower = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="7" y="2" width="10" height="20" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <rect x="9.5" y="4" width="5" height="3.5" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
  <circle cx="12" cy="10" r="1.5" stroke="currentColor" stroke-width="1.2"/>
  <line x1="9" y1="13.5" x2="15" y2="13.5" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.5"/>
  <line x1="9" y1="15.5" x2="15" y2="15.5" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.5"/>
  <line x1="9" y1="17.5" x2="15" y2="17.5" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.5"/>
  <circle cx="12" cy="20.5" r="0.7" fill="currentColor" opacity="0.6"/>
</svg>''';

  static const String acUnit = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="5" width="20" height="11" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="9" x2="19" y2="9" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <line x1="5" y1="11.5" x2="19" y2="11.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <line x1="5" y1="14" x2="19" y2="14" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <rect x="15" y="6.5" width="5" height="3" rx="0.4" fill="currentColor" opacity="0.25"/>
  <path d="M7 17 Q5 19 4 21" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
  <path d="M12 17 Q11 19 10 21" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
  <path d="M17 17 Q16 19 15 21" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
</svg>''';

  static const String window = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="3" width="18" height="18" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <line x1="3" y1="12" x2="21" y2="12" stroke="currentColor" stroke-width="1.5"/>
  <line x1="12" y1="3" x2="12" y2="21" stroke="currentColor" stroke-width="1.5"/>
  <rect x="4.5" y="4.5" width="6" height="6" rx="0.3" fill="currentColor" opacity="0.08"/>
  <rect x="13.5" y="4.5" width="6" height="6" rx="0.3" fill="currentColor" opacity="0.08"/>
  <rect x="4.5" y="13.5" width="6" height="6" rx="0.3" fill="currentColor" opacity="0.08"/>
  <rect x="13.5" y="13.5" width="6" height="6" rx="0.3" fill="currentColor" opacity="0.08"/>
</svg>''';

  static const String lamp = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <line x1="12" y1="11" x2="12" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="8" y1="21" x2="16" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M7 11 L12 3 L17 11 Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
  <line x1="7" y1="11" x2="17" y2="11" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <circle cx="12" cy="3.5" r="1" fill="currentColor" opacity="0.7"/>
</svg>''';

  static const String plant = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 20 L12 10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M12 14 Q8 13 7 9 Q11 8 12 12" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" fill="currentColor" opacity="0.15"/>
  <path d="M12 11 Q16 9 17 5 Q13 5 12 9" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" fill="currentColor" opacity="0.15"/>
  <rect x="9" y="17" width="6" height="5" rx="1" stroke="currentColor" stroke-width="1.4"/>
  <line x1="9.5" y1="19" x2="14.5" y2="19" stroke="currentColor" stroke-width="0.8" opacity="0.5"/>
</svg>''';

  static const String bookshelf = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="3" width="18" height="18" rx="1" stroke="currentColor" stroke-width="1.5"/>
  <line x1="3" y1="10" x2="21" y2="10" stroke="currentColor" stroke-width="1.3"/>
  <line x1="3" y1="16" x2="21" y2="16" stroke="currentColor" stroke-width="1.3"/>
  <rect x="5" y="4.5" width="2.5" height="4" rx="0.3" fill="currentColor" opacity="0.5"/>
  <rect x="8.5" y="4.5" width="3" height="4" rx="0.3" fill="currentColor" opacity="0.35"/>
  <rect x="12.5" y="4.5" width="2" height="4" rx="0.3" fill="currentColor" opacity="0.55"/>
  <rect x="15.5" y="4.5" width="3" height="4" rx="0.3" fill="currentColor" opacity="0.4"/>
  <rect x="5" y="11.5" width="3" height="3" rx="0.3" fill="currentColor" opacity="0.4"/>
  <rect x="9.5" y="11.5" width="2" height="3" rx="0.3" fill="currentColor" opacity="0.5"/>
  <rect x="13" y="11.5" width="3.5" height="3" rx="0.3" fill="currentColor" opacity="0.35"/>
</svg>''';

  static const String sofa = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="4" y="10" width="16" height="8" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <rect x="2" y="12" width="4" height="6" rx="2" stroke="currentColor" stroke-width="1.4"/>
  <rect x="18" y="12" width="4" height="6" rx="2" stroke="currentColor" stroke-width="1.4"/>
  <rect x="4" y="7" width="16" height="4" rx="1.5" stroke="currentColor" stroke-width="1.4"/>
  <line x1="7" y1="18" x2="7" y2="21" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="17" y1="18" x2="17" y2="21" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="10" y1="12" x2="14" y2="12" stroke="currentColor" stroke-width="1" opacity="0.4"/>
</svg>''';

  static const String wardrobe = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="3" width="18" height="19" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <line x1="12" y1="3" x2="12" y2="22" stroke="currentColor" stroke-width="1.4"/>
  <circle cx="10.5" cy="12" r="1" stroke="currentColor" stroke-width="1.2"/>
  <circle cx="13.5" cy="12" r="1" stroke="currentColor" stroke-width="1.2"/>
  <line x1="3" y1="7" x2="21" y2="7" stroke="currentColor" stroke-width="1.2" opacity="0.4"/>
</svg>''';

  static const String kitchen = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="12" width="20" height="9" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <rect x="2" y="4" width="20" height="9" rx="1" stroke="currentColor" stroke-width="1.4"/>
  <circle cx="9" cy="8.5" r="2" stroke="currentColor" stroke-width="1.3"/>
  <circle cx="15.5" cy="8.5" r="1.5" stroke="currentColor" stroke-width="1.2"/>
  <circle cx="9" cy="8.5" r="0.5" fill="currentColor" opacity="0.6"/>
  <line x1="6" y1="15.5" x2="11" y2="15.5" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="13" y1="15.5" x2="18" y2="15.5" stroke="currentColor" stroke-width="1" opacity="0.5"/>
</svg>''';

  static const String monitor = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="3" width="20" height="14" rx="1.5" stroke="currentColor" stroke-width="1.5"/>
  <line x1="12" y1="17" x2="12" y2="20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="8" y1="20" x2="16" y2="20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <rect x="4" y="5" width="16" height="9" rx="0.5" fill="currentColor" opacity="0.08"/>
  <line x1="4" y1="14.5" x2="20" y2="14.5" stroke="currentColor" stroke-width="0.8" opacity="0.3"/>
</svg>''';

  // ─── Preset / Room Type ──────────────────────────────────────────────────
  static const String gaming = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 9 Q2 9 2 14 L3 18 Q3.5 20 5.5 20 Q7 20 8 18.5 L9 17 L15 17 L16 18.5 Q17 20 18.5 20 Q20.5 20 21 18 L22 14 Q22 9 18 9 Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/>
  <line x1="9" y1="12" x2="9" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="8" y1="13" x2="10" y2="13" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="15" cy="12" r="0.8" fill="currentColor"/>
  <circle cx="17" cy="13.5" r="0.8" fill="currentColor"/>
  <circle cx="15" cy="15" r="0.8" fill="currentColor"/>
  <circle cx="13" cy="13.5" r="0.8" fill="currentColor"/>
</svg>''';

  static const String briefcase = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="8" width="20" height="14" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <path d="M8 8 L8 6 Q8 4 10 4 L14 4 Q16 4 16 6 L16 8" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="2" y1="13" x2="22" y2="13" stroke="currentColor" stroke-width="1.3"/>
  <rect x="10" y="11.5" width="4" height="3" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
</svg>''';

  static const String house = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3 12 L12 4 L21 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M5 10.5 L5 20 L19 20 L19 10.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <rect x="9.5" y="14" width="5" height="6" rx="0.5" stroke="currentColor" stroke-width="1.3"/>
  <rect x="6" y="13" width="4" height="3.5" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
  <rect x="14" y="13" width="4" height="3.5" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
</svg>''';

  static const String moon = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M21 12.8 A9 9 0 1 1 11.2 3 A7 7 0 0 0 21 12.8 Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="currentColor" opacity="0.12"/>
  <circle cx="17" cy="6" r="0.7" fill="currentColor" opacity="0.5"/>
  <circle cx="19" cy="9" r="0.5" fill="currentColor" opacity="0.4"/>
  <circle cx="15" cy="4" r="0.4" fill="currentColor" opacity="0.3"/>
</svg>''';

  // ─── Simulation modes ────────────────────────────────────────────────────
  static const String airflow = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3 8 Q8 8 10 6 Q12 4 14 4 Q17 4 17 7 Q17 10 14 10 L3 10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M3 13 Q9 13 11 15 Q13 17 16 17 Q19 17 19 14 Q19 11 16 11 L3 11" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" opacity="0.7"/>
  <path d="M3 16 Q6 16 8 18 Q9 19 11 19 Q13 19 13 17.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" opacity="0.45"/>
</svg>''';

  static const String lightbulb = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M9 21 L15 21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M10 18 L14 18" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <path d="M12 3 A6 6 0 0 1 18 9 Q18 12 15 14.5 L15 16 L9 16 L9 14.5 Q6 12 6 9 A6 6 0 0 1 12 3 Z" stroke="currentColor" stroke-width="1.5" fill="currentColor" opacity="0.1"/>
  <line x1="12" y1="10" x2="12" y2="13" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" opacity="0.5"/>
</svg>''';

  static const String ergonomics = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="4" r="2" stroke="currentColor" stroke-width="1.4"/>
  <path d="M8 9 Q12 7 16 9 L17 14 L14 14 L13 19 L11 19 L10 14 L7 14 Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" fill="currentColor" opacity="0.1"/>
  <path d="M8 9 L6 13" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <path d="M16 9 L18 13" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
</svg>''';

  // ─── UI / Actions ─────────────────────────────────────────────────────────
  static const String camera = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8 5 L9.5 3 L14.5 3 L16 5 L20 5 Q21 5 21 6 L21 18 Q21 19 20 19 L4 19 Q3 19 3 18 L3 6 Q3 5 4 5 Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
  <circle cx="12" cy="12" r="4" stroke="currentColor" stroke-width="1.4"/>
  <circle cx="12" cy="12" r="1.5" fill="currentColor" opacity="0.4"/>
</svg>''';

  static const String tune = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <line x1="3" y1="6" x2="21" y2="6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="3" y1="12" x2="21" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="3" y1="18" x2="21" y2="18" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="8" cy="6" r="2.5" fill="#0A0B0F" stroke="currentColor" stroke-width="1.4"/>
  <circle cx="15" cy="12" r="2.5" fill="#0A0B0F" stroke="currentColor" stroke-width="1.4"/>
  <circle cx="10" cy="18" r="2.5" fill="#0A0B0F" stroke="currentColor" stroke-width="1.4"/>
</svg>''';

  static const String speedometer = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M5 17 A8 8 0 1 1 19 17" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="12" y1="17" x2="16" y2="10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="12" cy="17" r="1.5" fill="currentColor"/>
  <line x1="7" y1="16" x2="8.5" y2="16" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
  <line x1="15.5" y1="16" x2="17" y2="16" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
  <line x1="12" y1="10" x2="12" y2="11.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.5"/>
</svg>''';

  static const String upgrade = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 3 L19 10 L15 10 L15 21 L9 21 L9 10 L5 10 Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" fill="currentColor" opacity="0.12"/>
</svg>''';

  static const String home = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3 12 L12 4 L21 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M5 10.5 L5 20 L19 20 L19 10.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <rect x="9.5" y="14" width="5" height="6" rx="0.5" stroke="currentColor" stroke-width="1.3"/>
</svg>''';

  static const String scan = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M4 8 L4 4 L8 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M16 4 L20 4 L20 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M4 16 L4 20 L8 20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M16 20 L20 20 L20 16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <line x1="3" y1="12" x2="21" y2="12" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" opacity="0.7"/>
</svg>''';

  static const String fan = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="2" stroke="currentColor" stroke-width="1.4"/>
  <path d="M12 10 Q12 6 14 4 Q18 4 18 8 Q18 10 14 10 Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
  <path d="M14 12 Q18 12 20 14 Q20 18 16 18 Q14 18 14 14 Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
  <path d="M12 14 Q12 18 10 20 Q6 20 6 16 Q6 14 10 14 Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
  <path d="M10 12 Q6 12 4 10 Q4 6 8 6 Q10 6 10 10 Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
</svg>''';

  static const String purifier = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="7" y="3" width="10" height="18" rx="3" stroke="currentColor" stroke-width="1.5"/>
  <line x1="10" y1="8" x2="14" y2="8" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <line x1="10" y1="10.5" x2="14" y2="10.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <line x1="10" y1="13" x2="14" y2="13" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" opacity="0.6"/>
  <circle cx="12" cy="17" r="1.5" stroke="currentColor" stroke-width="1.2"/>
</svg>''';

  static const String monitorArm = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="3" width="12" height="8" rx="1" stroke="currentColor" stroke-width="1.4"/>
  <line x1="9" y1="11" x2="9" y2="14" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <path d="M9 14 Q9 17 14 17 L14 20" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
  <line x1="12" y1="20" x2="16" y2="20" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
</svg>''';

  static const String cableTray = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="10" width="18" height="5" rx="1.5" stroke="currentColor" stroke-width="1.4"/>
  <line x1="7" y1="10" x2="7" y2="15" stroke="currentColor" stroke-width="1" opacity="0.4"/>
  <line x1="12" y1="10" x2="12" y2="15" stroke="currentColor" stroke-width="1" opacity="0.4"/>
  <line x1="17" y1="10" x2="17" y2="15" stroke="currentColor" stroke-width="1" opacity="0.4"/>
  <path d="M7 10 Q7 7 10 7" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
  <path d="M12 10 Q12 6 15 6 Q17 6 17 8 L17 10" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
</svg>''';

  static const String mat = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="15" width="18" height="5" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <line x1="6" y1="15" x2="6" y2="20" stroke="currentColor" stroke-width="0.9" opacity="0.4"/>
  <line x1="9" y1="15" x2="9" y2="20" stroke="currentColor" stroke-width="0.9" opacity="0.4"/>
  <line x1="12" y1="15" x2="12" y2="20" stroke="currentColor" stroke-width="0.9" opacity="0.4"/>
  <line x1="15" y1="15" x2="15" y2="20" stroke="currentColor" stroke-width="0.9" opacity="0.4"/>
  <line x1="18" y1="15" x2="18" y2="20" stroke="currentColor" stroke-width="0.9" opacity="0.4"/>
  <path d="M8 6 Q12 4 16 6 Q12 15 8 6 Z" stroke="currentColor" stroke-width="1.3" fill="currentColor" opacity="0.1"/>
</svg>''';

  static const String smartBlinds = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3" y="2" width="18" height="2" rx="1" fill="currentColor" opacity="0.6"/>
  <line x1="5" y1="6" x2="19" y2="6" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" opacity="0.8"/>
  <line x1="5" y1="10" x2="19" y2="10" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" opacity="0.6"/>
  <line x1="5" y1="14" x2="19" y2="14" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" opacity="0.4"/>
  <line x1="5" y1="18" x2="19" y2="18" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" opacity="0.25"/>
  <line x1="12" y1="3" x2="12" y2="22" stroke="currentColor" stroke-width="1" opacity="0.3"/>
</svg>''';

  static const String lightBar = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="4" y="10" width="16" height="4" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <line x1="7" y1="14" x2="6" y2="18" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" opacity="0.6"/>
  <line x1="10" y1="14" x2="10" y2="19" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" opacity="0.7"/>
  <line x1="12" y1="14" x2="12" y2="20" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
  <line x1="14" y1="14" x2="14" y2="19" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" opacity="0.7"/>
  <line x1="17" y1="14" x2="18" y2="18" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" opacity="0.6"/>
  <line x1="7" y1="10" x2="6" y2="6" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.3"/>
  <line x1="12" y1="10" x2="12" y2="5" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.3"/>
  <line x1="17" y1="10" x2="18" y2="6" stroke="currentColor" stroke-width="1" stroke-linecap="round" opacity="0.3"/>
</svg>''';

  static const String floorLamp = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <line x1="12" y1="8" x2="12" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="8" y1="21" x2="16" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M6 8 Q12 2 18 8 Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
  <line x1="6" y1="8" x2="18" y2="8" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
</svg>''';

  static const String trendingUp = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <polyline points="3,17 9,11 13,15 21,7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
  <polyline points="15,7 21,7 21,13" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const String trophy = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8 21 L16 21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="12" y1="17" x2="12" y2="21" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <path d="M5 3 L19 3 L19 10 Q19 15 12 17 Q5 15 5 10 Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" fill="currentColor" opacity="0.1"/>
  <path d="M5 5 Q2 5 2 8 Q2 11 5 11" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
  <path d="M19 5 Q22 5 22 8 Q22 11 19 11" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
</svg>''';

  static const String checkCircle = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.5"/>
  <polyline points="8,12 11,15 16,9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const String star = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" fill="currentColor" opacity="0.15"/>
</svg>''';

  static const String add = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.4"/>
  <line x1="12" y1="8" x2="12" y2="16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <line x1="8" y1="12" x2="16" y2="12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
</svg>''';

  static const String info = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.4"/>
  <line x1="12" y1="11" x2="12" y2="17" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
  <circle cx="12" cy="7.5" r="0.8" fill="currentColor"/>
</svg>''';

  static const String wallet = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="6" width="20" height="13" rx="2" stroke="currentColor" stroke-width="1.5"/>
  <circle cx="17" cy="12.5" r="1.5" stroke="currentColor" stroke-width="1.2"/>
  <path d="M2 10 L22 10" stroke="currentColor" stroke-width="1.2" opacity="0.6"/>
</svg>''';
}

/// Renders an inline SVG string as a widget.
class SvgIcon extends StatelessWidget {
  final String svgString;
  final double size;
  final Color? color;

  const SvgIcon(this.svgString, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}

/// Maps a furniture id/name to its SVG string.
String furnitureSvgFor(String id) {
  switch (id.toLowerCase()) {
    case 'bed': return RoomSvg.bed;
    case 'desk': return RoomSvg.desk;
    case 'chair': return RoomSvg.chair;
    case 'monitor': return RoomSvg.monitor;
    case 'pc': return RoomSvg.pcTower;
    case 'ac': return RoomSvg.acUnit;
    case 'window': return RoomSvg.window;
    case 'lamp': return RoomSvg.lamp;
    case 'plant': return RoomSvg.plant;
    case 'bookshelf': return RoomSvg.bookshelf;
    case 'sofa': return RoomSvg.sofa;
    case 'wardrobe': return RoomSvg.wardrobe;
    case 'kitchen': return RoomSvg.kitchen;
    case 'shelf': return RoomSvg.bookshelf;
    default: return RoomSvg.house;
  }
}

/// Maps a preset enum name to its SVG string.
String presetSvgFor(String name) {
  switch (name.toLowerCase()) {
    case 'gaming setup': return RoomSvg.gaming;
    case 'home office': return RoomSvg.briefcase;
    case 'studio apartment': return RoomSvg.house;
    case 'minimalist bedroom': return RoomSvg.moon;
    default: return RoomSvg.home;
  }
}

/// Maps an upgrade icon name to its SVG string.
String upgradeSvgFor(String iconName) {
  switch (iconName) {
    case 'fan': return RoomSvg.fan;
    case 'purifier': return RoomSvg.purifier;
    case 'lightBar': return RoomSvg.lightBar;
    case 'floorLamp': return RoomSvg.floorLamp;
    case 'monitorArm': return RoomSvg.monitorArm;
    case 'cableTray': return RoomSvg.cableTray;
    case 'mat': return RoomSvg.mat;
    case 'smartBlinds': return RoomSvg.smartBlinds;
    default: return RoomSvg.upgrade;
  }
}
