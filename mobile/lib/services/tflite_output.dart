/// Output buffer for a `[1, size]` tensor. `tflite_flutter` compares the buffer's
/// shape with the tensor's and throws on a mismatch, so a flat list cannot work.
/// Read the scores from index 0 after `run`.
List<List<double>> singleBatchOutput(int size) => [
      List<double>.filled(size, 0.0),
    ];
