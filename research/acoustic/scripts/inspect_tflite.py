"""Print a TFLite model's input/output tensors, op set and whether it needs Select TF ops.

Usage: python scripts/inspect_tflite.py <model.tflite> [more.tflite ...]
"""
import sys

import numpy as np
from ai_edge_litert.interpreter import Interpreter


def describe(path: str) -> None:
    interp = Interpreter(model_path=path)
    print(f"== {path}")
    for kind, details in (("input", interp.get_input_details()), ("output", interp.get_output_details())):
        for d in details:
            print(
                f"  {kind}: name={d['name']!r} index={d['index']} shape={list(d['shape'])} "
                f"shape_signature={list(d.get('shape_signature', []))} dtype={np.dtype(d['dtype']).name} "
                f"quant={d['quantization']}"
            )
    ops = sorted({op["op_name"] for op in interp._get_ops_details()})
    print(f"  ops ({len(ops)}): {', '.join(ops)}")
    flex = [o for o in ops if o.startswith("Flex") or o == "DELEGATE" or "Custom" in o]
    print(f"  select-tf/custom ops: {flex or 'none'}")
    tensors = interp.get_tensor_details()
    print(f"  tensors: {len(tensors)}; dtypes: {sorted({np.dtype(t['dtype']).name for t in tensors})}")
    # Any intermediate 1024-wide tensor (YAMNet's embedding) that is not an output?
    wide = [t for t in tensors if 1024 in list(t["shape"])[-1:]]
    for t in wide[:6]:
        print(f"  1024-wide tensor: {t['name']!r} shape={list(t['shape'])}")


for p in sys.argv[1:]:
    describe(p)
