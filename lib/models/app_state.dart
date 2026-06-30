// lib/models/app_state.dart
import 'package:flutter/foundation.dart';
import 'room_model.dart';

class AppState extends ChangeNotifier {
  // Navigation
  int _currentTab = 0;
  int get currentTab => _currentTab;

  void setTab(int tab) {
    _currentTab = tab;
    notifyListeners();
  }

  // Scan state
  bool _scanComplete = false;
  bool get scanComplete => _scanComplete;
  double _scanProgress = 0.0;
  double get scanProgress => _scanProgress;

  void setScanProgress(double p) {
    _scanProgress = p;
    if (p >= 1.0) _scanComplete = true;
    notifyListeners();
  }

  void resetScan() {
    _scanProgress = 0.0;
    _scanComplete = false;
    notifyListeners();
  }

  // Selected Room
  RoomPreset _selectedPreset = RoomPreset.gamingSetup;
  RoomPreset get selectedPreset => _selectedPreset;
  late List<FurnitureItem> _furniture;

  AppState() {
    _loadPreset(RoomPreset.gamingSetup);
  }

  void _loadPreset(RoomPreset preset) {
    final data = RoomPresets.getPreset(preset);
    _furniture = List.from(data.furniture.map((f) => f.copyWith()));
    _selectedPreset = preset;
  }

  List<FurnitureItem> get furniture => _furniture;
  RoomData get currentRoomData => RoomPresets.getPreset(_selectedPreset);

  void selectPreset(RoomPreset preset) {
    _loadPreset(preset);
    _scanComplete = false;
    _scanProgress = 0.0;
    _isOptimized = false;
    notifyListeners();
  }

  void moveFurniture(String id, double newX, double newY) {
    final idx = _furniture.indexWhere((f) => f.id == id);
    if (idx >= 0) {
      _furniture[idx] = _furniture[idx].copyWith(gridX: newX, gridY: newY);
      notifyListeners();
    }
  }

  // Optimization sliders
  double _airflowSlider = 0.7;
  double _lightingSlider = 0.5;
  double _ergonomicsSlider = 0.6;

  double get airflowSlider => _airflowSlider;
  double get lightingSlider => _lightingSlider;
  double get ergonomicsSlider => _ergonomicsSlider;

  void setAirflowSlider(double v) { _airflowSlider = v; notifyListeners(); }
  void setLightingSlider(double v) { _lightingSlider = v; notifyListeners(); }
  void setErgonomicsSlider(double v) { _ergonomicsSlider = v; notifyListeners(); }

  // Scores
  bool _isOptimized = false;
  bool get isOptimized => _isOptimized;

  double get _baseAirflowScore {
    double score = 50;
    for (final f in _furniture) { score += f.airflowImpact * 15; }
    return score.clamp(0, 100);
  }

  double get _baseLightingScore {
    double score = 40;
    for (final f in _furniture) { score += f.lightingImpact * 12; }
    return score.clamp(0, 100);
  }

  double get _baseErgonomicsScore {
    double score = 45;
    for (final f in _furniture) { score += f.ergonomicsImpact * 13; }
    return score.clamp(0, 100);
  }

  double get airflowScore => _isOptimized
      ? (_baseAirflowScore + _airflowSlider * 25).clamp(0, 100)
      : _baseAirflowScore;

  double get lightingScore => _isOptimized
      ? (_baseLightingScore + _lightingSlider * 25).clamp(0, 100)
      : _baseLightingScore;

  double get ergonomicsScore => _isOptimized
      ? (_baseErgonomicsScore + _ergonomicsSlider * 25).clamp(0, 100)
      : _baseErgonomicsScore;

  double get overallScore {
    final total = _airflowSlider + _lightingSlider + _ergonomicsSlider;
    if (total == 0) return (airflowScore + lightingScore + ergonomicsScore) / 3;
    return (airflowScore * _airflowSlider +
            lightingScore * _lightingSlider +
            ergonomicsScore * _ergonomicsSlider) /
        total;
  }

  double get previousOverallScore =>
      (_baseAirflowScore + _baseLightingScore + _baseErgonomicsScore) / 3;

  String get scoreGrade {
    final s = overallScore;
    if (s >= 90) return 'S';
    if (s >= 80) return 'A';
    if (s >= 70) return 'B';
    if (s >= 55) return 'C';
    return 'D';
  }

  void runOptimization() {
    _isOptimized = true;
    notifyListeners();
  }

  // Room Shape Layout support
  String _roomShape = 'Rectangular';
  String get roomShape => _roomShape;
  
  void setRoomShape(String shape) {
    _roomShape = shape;
    notifyListeners();
  }

  // Budget tracking properties
  double get totalBudget => 4000.0;
  
  double get baseRoomCost {
    double total = 0;
    for (final f in _furniture) {
      total += f.cost;
    }
    return total;
  }

  double get upgradesCost {
    double total = 0;
    for (final u in upgrades) {
      if (u['added'] as bool) {
        total += u['price'] as double;
      }
    }
    return total;
  }

  double get totalSpent => baseRoomCost + upgradesCost;
  double get budgetRemaining => totalBudget - totalSpent;

  // Benchmark simulation mode
  String _benchmarkMode = 'airflow';
  String get benchmarkMode => _benchmarkMode;

  void setBenchmarkMode(String mode) {
    _benchmarkMode = mode;
    notifyListeners();
  }

  // Upgrade catalog — icon names reference upgradeSvgFor() with price tags
  final List<Map<String, dynamic>> upgrades = [
    {'name': 'Air Circulator Fan', 'iconName': 'fan', 'type': 'airflow', 'desc': 'Reduces stagnant zones by 40%', 'airflowBoost': 15.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 0.0, 'price': 89.0, 'added': false},
    {'name': 'Smart Air Purifier', 'iconName': 'purifier', 'type': 'airflow', 'desc': 'Cleans and circulates air continuously', 'airflowBoost': 10.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 5.0, 'price': 189.0, 'added': false},
    {'name': 'Smart Light Bar', 'iconName': 'lightBar', 'type': 'lighting', 'desc': 'Bias lighting reduces eye strain 60%', 'airflowBoost': 0.0, 'lightingBoost': 18.0, 'ergonomicsBoost': 5.0, 'price': 99.0, 'added': false},
    {'name': 'Diffused Floor Lamp', 'iconName': 'floorLamp', 'type': 'lighting', 'desc': 'Soft ambient glow, no harsh shadows', 'airflowBoost': 0.0, 'lightingBoost': 12.0, 'ergonomicsBoost': 2.0, 'price': 79.0, 'added': false},
    {'name': 'Monitor Arm', 'iconName': 'monitorArm', 'type': 'ergonomics', 'desc': 'Frees desk space, optimizes eye level', 'airflowBoost': 5.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 20.0, 'price': 129.0, 'added': false},
    {'name': 'Cable Tray', 'iconName': 'cableTray', 'type': 'ergonomics', 'desc': 'Eliminates cable clutter, improves airflow', 'airflowBoost': 8.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 10.0, 'price': 39.0, 'added': false},
    {'name': 'Anti-Fatigue Mat', 'iconName': 'mat', 'type': 'ergonomics', 'desc': 'Reduces standing fatigue by 55%', 'airflowBoost': 0.0, 'lightingBoost': 0.0, 'ergonomicsBoost': 15.0, 'price': 49.0, 'added': false},
    {'name': 'Smart Blinds', 'iconName': 'smartBlinds', 'type': 'lighting', 'desc': 'Auto-adjusts glare throughout the day', 'airflowBoost': 2.0, 'lightingBoost': 14.0, 'ergonomicsBoost': 0.0, 'price': 249.0, 'added': false},
  ];

  double _upgradeAirflowBonus = 0;
  double _upgradeLightingBonus = 0;
  double _upgradeErgonomicsBonus = 0;

  double get upgradeAirflowBonus => _upgradeAirflowBonus;
  double get upgradeLightingBonus => _upgradeLightingBonus;
  double get upgradeErgonomicsBonus => _upgradeErgonomicsBonus;

  void toggleUpgrade(int index) {
    final u = upgrades[index];
    u['added'] = !(u['added'] as bool);
    _recalcUpgrades();
    notifyListeners();
  }

  void _recalcUpgrades() {
    _upgradeAirflowBonus = 0;
    _upgradeLightingBonus = 0;
    _upgradeErgonomicsBonus = 0;
    for (final u in upgrades) {
      if (u['added'] as bool) {
        _upgradeAirflowBonus += u['airflowBoost'] as double;
        _upgradeLightingBonus += u['lightingBoost'] as double;
        _upgradeErgonomicsBonus += u['ergonomicsBoost'] as double;
      }
    }
  }
}
