/// Every clinical and operational constant in the app, in one place.
///
/// `src/parameters.py` is the server's counterpart. `tests/test_parameters.py` fails
/// if the values both sides share ever differ. `docs/PARAMETERS_SIGNOFF.md` lists each
/// value for clinical review. All are unapproved placeholders until that sheet is signed.
library;

class MoewsBand {
  const MoewsBand({
    this.redBelow,
    this.yellowLowMin,
    this.yellowLowMax,
    this.yellowHighMin,
    this.yellowHighMax,
    this.redAbove,
  });

  final num? redBelow;
  final num? yellowLowMin;
  final num? yellowLowMax;
  final num? yellowHighMin;
  final num? yellowHighMax;
  final num? redAbove;
}

abstract final class Parameters {
  // Entry limits: these catch typos and impossible readings. They do not judge risk.
  static const systolicBpMin = 0;
  static const systolicBpMax = 300;
  static const diastolicBpMin = 0;
  static const diastolicBpMax = 200;
  static const heartRateMin = 0;
  static const heartRateMax = 300;
  static const respiratoryRateMin = 0;
  static const respiratoryRateMax = 120;
  static const temperatureMin = 20;
  static const temperatureMax = 45;
  static const spo2Min = 0;
  static const spo2Max = 100;

  // MOEWS bands (spec 9.3).
  static const systolicBpBand = MoewsBand(
      redBelow: 80,
      yellowLowMin: 80,
      yellowLowMax: 90,
      yellowHighMin: 140,
      yellowHighMax: 150,
      redAbove: 150);
  static const diastolicBpBand = MoewsBand(
      redBelow: 60, yellowHighMin: 90, yellowHighMax: 100, redAbove: 100);
  static const heartRateBand = MoewsBand(
      redBelow: 50,
      yellowLowMin: 50,
      yellowLowMax: 60,
      yellowHighMin: 110,
      yellowHighMax: 130,
      redAbove: 130);
  static const respiratoryRateBand = MoewsBand(
      redBelow: 10,
      yellowLowMin: 10,
      yellowLowMax: 14,
      yellowHighMin: 24,
      yellowHighMax: 30,
      redAbove: 30);
  static const temperatureBand = MoewsBand(
      redBelow: 35,
      yellowLowMin: 35,
      yellowLowMax: 36,
      yellowHighMin: 38,
      yellowHighMax: 39,
      redAbove: 39);
  static const spo2Band =
      MoewsBand(redBelow: 90, yellowLowMin: 90, yellowLowMax: 94);
  static const moewsRedParameterScore = 3;
  static const moewsRedTotal = 5;
  static const moewsYellowTotal = 3;

  // Acoustic screening (app only).
  static const acousticRedAbove = 0.7;
  static const acousticInconclusiveBelow = 0.5;
  static const operaGreenAbove = 0.7;
  static const defaultScreeningSeconds = 15;

  // Typed-in device readings (app only).
  static const deviceHeartRateMin = 30;
  static const deviceHeartRateMax = 250;
  static const deviceSpo2Min = 50;
  static const deviceSpo2Max = 100;

  // Facility catalog (app only).
  static const catalogStaleAfterDays = 30;
}
