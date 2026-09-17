// Fact-check guards: comfort heuristics behave as documented and move Bench signals.
import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/models/room_model.dart';
import 'package:room_rig/services/comfort_heuristics.dart';
import 'package:room_rig/services/ergonomics_optimizer.dart';
import 'package:room_rig/services/lighting_optimizer.dart';

void main() {
  FurnitureItem item({
    required String id,
    required String icon,
    required double x,
    required double y,
    double w = 1,
    double h = 1,
  }) =>
      FurnitureItem(
        id: id,
        name: id,
        iconName: icon,
        category: 'test',
        gridX: x,
        gridY: y,
        width: w,
        height: h,
      );

  test('door prospect: facing door scores higher than back-to-door', () {
    final desk = item(id: 'desk', icon: 'desk', x: 3, y: 3, w: 2, h: 1);
    final door = item(id: 'door', icon: 'door', x: 0, y: 3.2, w: 1, h: 1); // west wall
    // Chair east of desk → faces west toward desk and door beyond.
    final facing = item(id: 'chair', icon: 'chair', x: 5.2, y: 3.2);
    // Chair west of desk → faces east toward desk; door is behind the seat.
    final back = item(id: 'chair', icon: 'chair', x: 1.5, y: 3.2);
    final good = ComfortHeuristics.doorProspectScore(chair: facing, desk: desk, door: door);
    final bad = ComfortHeuristics.doorProspectScore(chair: back, desk: desk, door: door);
    expect(good, greaterThan(bad));
  });

  test('bed privacy: offset from door axis scores higher than in the inbound lane', () {
    final door = item(id: 'door', icon: 'door', x: 0, y: 6, w: 1, h: 1);
    final inLane = item(id: 'bed', icon: 'bed', x: 0.2, y: 4.5, w: 2, h: 2);
    final offset = item(id: 'bed', icon: 'bed', x: 3.5, y: 5.5, w: 2, h: 2);
    final a = ComfortHeuristics.bedPrivacyFromDoor(
      bed: inLane,
      door: door,
      gridCols: 6,
      gridRows: 8,
    );
    final b = ComfortHeuristics.bedPrivacyFromDoor(
      bed: offset,
      door: door,
      gridCols: 6,
      gridRows: 8,
    );
    expect(b, greaterThan(a));
  });

  test('window side-light: perpendicular desk beats square-on', () {
    final window = item(id: 'window', icon: 'window', x: 2, y: 0, w: 2, h: 0.3);
    final deskSide = item(id: 'desk', icon: 'desk', x: 0.3, y: 2, w: 2, h: 1);
    final chairSide = item(id: 'chair', icon: 'chair', x: 0.5, y: 3.2);
    final deskFront = item(id: 'desk', icon: 'desk', x: 2, y: 1.2, w: 2, h: 1);
    final chairFront = item(id: 'chair', icon: 'chair', x: 2.4, y: 2.4);
    final side = ComfortHeuristics.windowSideLightScore(
      desk: deskSide,
      chair: chairSide,
      window: window,
    );
    final front = ComfortHeuristics.windowSideLightScore(
      desk: deskFront,
      chair: chairFront,
      window: window,
    );
    expect(side, greaterThan(front));
  });

  test('HVAC clearance: furniture on the vent scores worse than clear', () {
    final ac = item(id: 'ac', icon: 'ac', x: 5, y: 2, w: 1, h: 1);
    final clearShelf = item(id: 'shelf', icon: 'shelf', x: 0, y: 6, w: 1, h: 1);
    final blocking = item(id: 'shelf', icon: 'shelf', x: 4.6, y: 2, w: 1, h: 1);
    final good = ComfortHeuristics.hvacClearanceScore([ac, clearShelf]);
    final bad = ComfortHeuristics.hvacClearanceScore([ac, blocking]);
    expect(good, greaterThan(bad));
  });

  test('gaming Auto-Rig does not invent ISO/ASHRAE/CPTED certification phrases', () {
    final room = RoomPresets.getPreset(RoomPreset.gamingSetup);
    final ergo = ErgonomicsOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final light = LightingOptimizer.optimize(
      furniture: room.furniture,
      gridCols: room.gridCols,
      gridRows: room.gridRows,
    );
    final banned = RegExp(r'\b(ISO 9241|BIFMA|CPTED|ASHRAE|WELL)\b', caseSensitive: false);
    for (final r in [...ergo.reasons, ...light.reasons]) {
      expect(banned.hasMatch(r), isFalse, reason: r);
    }
  });
}
