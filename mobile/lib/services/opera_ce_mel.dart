import 'dart:math' as math;
import 'dart:typed_data';

/// OPERA-CE mel frontend (librosa-compatible defaults used by upstream).
///
/// Matches `src/acoustic/opera_ce_mel.py` / OPERA `pre_process_audio_mel_t`
/// with `f_max=8000`, then min-max normalizes to \[0, 1\].
class OperaCeMel {
  static const int sampleRate = 16000;
  static const int nMels = 64;
  static const double fMin = 50.0;
  static const double fMax = 8000.0;
  static const int nFft = 1024;
  static const int hop = 512;
  static const int targetSamples = 8 * sampleRate;
  static const int melFrames = 251;
  static const int melBins = nMels;

  /// Pad/trim PCM float samples to 8 s @ 16 kHz, then mel → (251, 64).
  static Float32List melForEncoder(List<double> samples) {
    final trimmed = padOrTrim(samples);
    final mel = preProcessAudioMelT(trimmed);
    return _ensureFrames(mel);
  }

  static List<double> padOrTrim(List<double> audio, {int length = targetSamples}) {
    if (audio.length >= length) {
      return audio.sublist(0, length);
    }
    final out = List<double>.filled(length, 0.0);
    for (var i = 0; i < audio.length; i++) {
      out[i] = audio[i];
    }
    return out;
  }

  /// Returns row-major (frames × nMels) float32 list.
  static Float32List preProcessAudioMelT(List<double> audio) {
    final power = _stftPower(audio);
    final filters = _melFilterbank();
    final nFrames = power.length ~/ (nFft ~/ 2 + 1);
    final nFreq = nFft ~/ 2 + 1;
    final mel = Float32List(nFrames * nMels);

    for (var t = 0; t < nFrames; t++) {
      for (var m = 0; m < nMels; m++) {
        var sum = 0.0;
        final fBase = m * nFreq;
        final pBase = t * nFreq;
        for (var f = 0; f < nFreq; f++) {
          sum += filters[fBase + f] * power[pBase + f];
        }
        mel[t * nMels + m] = sum;
      }
    }

    // power_to_db(ref=max)
    var maxP = mel[0];
    for (var i = 1; i < mel.length; i++) {
      if (mel[i] > maxP) maxP = mel[i];
    }
    if (maxP <= 0) maxP = 1e-10;
    const amin = 1e-10;
    const topDb = 80.0;
    var maxDb = -double.infinity;
    for (var i = 0; i < mel.length; i++) {
      final db = 10.0 * math.log(math.max(amin, mel[i]) / maxP) / math.ln10;
      mel[i] = db;
      if (db > maxDb) maxDb = db;
    }
    for (var i = 0; i < mel.length; i++) {
      mel[i] = math.max(mel[i], maxDb - topDb);
    }

    // min-max to [0, 1]
    var lo = mel[0];
    var hi = mel[0];
    for (var i = 1; i < mel.length; i++) {
      if (mel[i] < lo) lo = mel[i];
      if (mel[i] > hi) hi = mel[i];
    }
    if (hi != lo) {
      for (var i = 0; i < mel.length; i++) {
        mel[i] = (mel[i] - lo) / (hi - lo);
      }
    }
    return mel;
  }

  static Float32List _ensureFrames(Float32List mel) {
    final frames = mel.length ~/ nMels;
    final out = Float32List(melFrames * nMels);
    final copyFrames = math.min(frames, melFrames);
    for (var t = 0; t < copyFrames; t++) {
      for (var m = 0; m < nMels; m++) {
        out[t * nMels + m] = mel[t * nMels + m];
      }
    }
    return out;
  }

  /// Row-major power spectrogram (frames × nFreq).
  static Float32List _stftPower(List<double> audio) {
    final pad = nFft ~/ 2;
    final padded = List<double>.filled(audio.length + 2 * pad, 0.0);
    // librosa default pad_mode='constant' (zeros)
    for (var i = 0; i < audio.length; i++) {
      padded[pad + i] = audio[i];
    }

    final nFrames = 1 + (padded.length - nFft) ~/ hop;
    final nFreq = nFft ~/ 2 + 1;
    final window = _hann(nFft);
    final out = Float32List(nFrames * nFreq);
    final re = Float64List(nFft);
    final im = Float64List(nFft);

    for (var t = 0; t < nFrames; t++) {
      final start = t * hop;
      for (var i = 0; i < nFft; i++) {
        re[i] = padded[start + i] * window[i];
        im[i] = 0.0;
      }
      _fftInPlace(re, im);
      for (var f = 0; f < nFreq; f++) {
        out[t * nFreq + f] = re[f] * re[f] + im[f] * im[f];
      }
    }
    return out;
  }

  static List<double> _hann(int n) {
    final w = List<double>.filled(n, 0.0);
    if (n == 1) {
      w[0] = 1.0;
      return w;
    }
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    }
    return w;
  }

  /// Slaney-style mel filterbank (librosa htk=False), shape (nMels × nFreq).
  static Float32List _melFilterbank() {
    final nFreq = nFft ~/ 2 + 1;
    final weights = Float32List(nMels * nFreq);
    final fftFreqs = List<double>.generate(
      nFreq,
      (i) => i * sampleRate / nFft,
    );

    final melFMin = _hzToMel(fMin);
    final melFMax = _hzToMel(fMax);
    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => melFMin + (melFMax - melFMin) * i / (nMels + 1),
    );
    final hzPoints = melPoints.map(_melToHz).toList();

    for (var m = 0; m < nMels; m++) {
      final lower = hzPoints[m];
      final mid = hzPoints[m + 1];
      final upper = hzPoints[m + 2];
      for (var f = 0; f < nFreq; f++) {
        final freq = fftFreqs[f];
        var w = 0.0;
        if (freq >= lower && freq <= mid && mid > lower) {
          w = (freq - lower) / (mid - lower);
        } else if (freq > mid && freq <= upper && upper > mid) {
          w = (upper - freq) / (upper - mid);
        }
        // Slaney normalize by bandwidth
        if (upper > lower) {
          w *= 2.0 / (upper - lower);
        }
        weights[m * nFreq + f] = w;
      }
    }
    return weights;
  }

  // librosa Slaney mel
  static double _hzToMel(double hz) {
    const fSp = 200.0 / 3;
    const minLogHz = 1000.0;
    const minLogMel = minLogHz / fSp;
    const logStep = 0.06875177717478254; // ln(6.4)/27
    if (hz >= minLogHz) {
      return minLogMel + math.log(hz / minLogHz) / logStep;
    }
    return hz / fSp;
  }

  static double _melToHz(double mel) {
    const fSp = 200.0 / 3;
    const minLogHz = 1000.0;
    const minLogMel = minLogHz / fSp;
    const logStep = 0.06875177717478254;
    if (mel >= minLogMel) {
      return minLogHz * math.exp(logStep * (mel - minLogMel));
    }
    return fSp * mel;
  }

  /// In-place Cooley–Tukey FFT (n must be power of 2).
  static void _fftInPlace(Float64List re, Float64List im) {
    final n = re.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wlenRe = math.cos(ang);
      final wlenIm = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var wRe = 1.0;
        var wIm = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final uRe = re[i + k];
          final uIm = im[i + k];
          final vRe = re[i + k + len ~/ 2] * wRe - im[i + k + len ~/ 2] * wIm;
          final vIm = re[i + k + len ~/ 2] * wIm + im[i + k + len ~/ 2] * wRe;
          re[i + k] = uRe + vRe;
          im[i + k] = uIm + vIm;
          re[i + k + len ~/ 2] = uRe - vRe;
          im[i + k + len ~/ 2] = uIm - vIm;
          final nextWRe = wRe * wlenRe - wIm * wlenIm;
          wIm = wRe * wlenIm + wIm * wlenRe;
          wRe = nextWRe;
        }
      }
    }
  }
}
