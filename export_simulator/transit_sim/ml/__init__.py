"""AI correction layer.

The physics simulator predicts survival from first principles. The AI layer learns where that
prediction is systematically wrong, using completed shipments (predicted vs actually observed),
and corrects future predictions. Until real shipment records exist it is trained on SIMULATED
shipments from a "pretend reality" (see ``synthetic.py``); real data uses the same CSV format and
simply replaces the simulated file.
"""
