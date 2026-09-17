// Human-readable before/after lines for Auto-Rig / Bench Apply.
import 'airflow_simulator.dart';
import 'ergonomics_simulator.dart';
import 'lighting_simulator.dart';

class LayoutScoreExplain {
  LayoutScoreExplain._();

  static List<String> airflow(AirflowMetrics before, AirflowMetrics after) {
    final out = <String>[];
    final deadDelta = (before.deadZoneRatio - after.deadZoneRatio) * 100;
    if (deadDelta >= 0.4) {
      out.add('Less dead air (−${deadDelta.toStringAsFixed(0)}% stagnant floor)');
    } else if (deadDelta <= -0.4) {
      out.add('Dead-air pockets grew (+${(-deadDelta).toStringAsFixed(0)}%)');
    }
    final heatDelta = (before.heatPocketRatio - after.heatPocketRatio) * 100;
    if (heatDelta >= 0.4) {
      out.add('Fewer heat pockets (−${heatDelta.toStringAsFixed(0)}%)');
    }
    final exitDelta = after.exitChannelScore - before.exitChannelScore;
    if (exitDelta >= 1.0) {
      out.add('Stronger exit channeling (+${exitDelta.toStringAsFixed(0)}) — air reaches door/exhaust');
    }
    final coolDelta = after.workZoneCooling - before.workZoneCooling;
    if (coolDelta >= 1.0) {
      out.add('Better work-zone cooling (+${coolDelta.toStringAsFixed(0)})');
    }
    final hvacDelta = after.hvacClearance - before.hvacClearance;
    if (hvacDelta >= 2.0) {
      out.add('HVAC faces clearer of furniture (+${hvacDelta.toStringAsFixed(0)})');
    }
    final circDelta = after.circulationScore - before.circulationScore;
    if (out.isEmpty && circDelta.abs() >= 0.3) {
      out.add(
        circDelta >= 0
            ? 'Circulation +${circDelta.toStringAsFixed(1)}'
            : 'Circulation ${circDelta.toStringAsFixed(1)}',
      );
    }
    return out;
  }

  static List<String> lighting(LightingMetrics before, LightingMetrics after) {
    final out = <String>[];
    final taskDelta = (after.taskIllumination - before.taskIllumination) * 100;
    if (taskDelta >= 1.0) {
      out.add('Brighter desk/chair task light (+${taskDelta.toStringAsFixed(0)})');
    }
    final shadowDelta = (before.shadowRatio - after.shadowRatio) * 100;
    if (shadowDelta >= 1.0) {
      out.add('Fewer under-lit floor patches (−${shadowDelta.toStringAsFixed(0)}%)');
    }
    final glareDelta = (before.glareRisk - after.glareRisk) * 100;
    if (glareDelta >= 2.0) {
      out.add('Lower glare risk at the desk (−${glareDelta.toStringAsFixed(0)})');
    }
    final sideDelta = (after.sideLightScore - before.sideLightScore) * 100;
    if (sideDelta >= 3.0) {
      out.add(
        'Better side-light geometry vs window (+${sideDelta.toStringAsFixed(0)}, OSHA-style guidance)',
      );
    }
    final dayDelta = (after.daylightReach - before.daylightReach) * 100;
    if (dayDelta >= 1.0) {
      out.add('Daylight reaches farther into the room (+${dayDelta.toStringAsFixed(0)})');
    }
    return out;
  }

  static List<String> ergonomics(ErgonomicsMetrics before, ErgonomicsMetrics after) {
    final out = <String>[];
    final pathDelta = (after.pathScore - before.pathScore) * 100;
    if (pathDelta >= 1.0) {
      out.add('Shorter / straighter frequent walks (+${pathDelta.toStringAsFixed(0)} path quality)');
    }
    final prospectDelta = (after.doorProspect - before.doorProspect) * 100;
    if (prospectDelta >= 2.0) {
      out.add('Better door visibility from the seat (+${prospectDelta.toStringAsFixed(0)})');
    } else if (after.doorProspect >= 0.7 && before.doorProspect < 0.7) {
      out.add('Seat no longer turns its back to the door');
    }
    final privacyDelta = (after.bedPrivacy - before.bedPrivacy) * 100;
    if (privacyDelta >= 3.0) {
      out.add('Bed farther off the door sightline (+${privacyDelta.toStringAsFixed(0)} privacy)');
    }
    final clearDelta = (after.chairClearance - before.chairClearance) * 100;
    if (clearDelta >= 2.0) {
      out.add('More chair pull-back clearance (+${clearDelta.toStringAsFixed(0)})');
    }
    final reachDelta = (after.reachScore - before.reachScore) * 100;
    if (reachDelta >= 2.0) {
      out.add('Gear closer in seated reach (+${reachDelta.toStringAsFixed(0)})');
    }
    return out;
  }
}
