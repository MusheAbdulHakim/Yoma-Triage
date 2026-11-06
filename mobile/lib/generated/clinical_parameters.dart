// GENERATED from config/clinical_parameters.json. Do not edit by hand.
// Run: python scripts/generate_clinical_params.py

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

abstract final class ClinicalParameters {
  static const version = '2026-11-06-draft';

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

  static const systolicBpBand = MoewsBand(
    redBelow: 80,
    yellowLowMin: 80,
    yellowLowMax: 90,
    yellowHighMin: 140,
    yellowHighMax: 150,
    redAbove: 150,
  );
  static const diastolicBpBand = MoewsBand(
    redBelow: 60,
    yellowLowMin: null,
    yellowLowMax: null,
    yellowHighMin: 90,
    yellowHighMax: 100,
    redAbove: 100,
  );
  static const heartRateBand = MoewsBand(
    redBelow: 50,
    yellowLowMin: 50,
    yellowLowMax: 60,
    yellowHighMin: 110,
    yellowHighMax: 130,
    redAbove: 130,
  );
  static const respiratoryRateBand = MoewsBand(
    redBelow: 10,
    yellowLowMin: 10,
    yellowLowMax: 14,
    yellowHighMin: 24,
    yellowHighMax: 30,
    redAbove: 30,
  );
  static const temperatureBand = MoewsBand(
    redBelow: 35,
    yellowLowMin: 35,
    yellowLowMax: 36,
    yellowHighMin: 38,
    yellowHighMax: 39,
    redAbove: 39,
  );
  static const spo2Band = MoewsBand(
    redBelow: 90,
    yellowLowMin: 90,
    yellowLowMax: 94,
    yellowHighMin: null,
    yellowHighMax: null,
    redAbove: null,
  );

  static const moewsRiskRedParameterScore = 3;
  static const moewsRiskRedTotal = 5;
  static const moewsRiskYellowTotal = 3;
  static const acousticRedAbove = 0.7;
  static const acousticInconclusiveBelow = 0.5;
  static const acousticOperaGreenAbove = 0.7;
  static const acousticDefaultScreeningSeconds = 15;
  static const advisoryDeviceHeartRateMin = 30;
  static const advisoryDeviceHeartRateMax = 250;
  static const advisoryDeviceSpo2Min = 50;
  static const advisoryDeviceSpo2Max = 100;
  static const catalogStaleAfterDays = 30;
}
