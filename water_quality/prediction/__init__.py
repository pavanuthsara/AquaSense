"""AquaSense prediction layer: forecasts water-quality parameters and raises
early (lead-time) alerts before a value leaves its safe range.

Kept separate from the controller's threshold engine (controller/engines) so a
cause-analysis layer can later sit on top of both.

    settings.py   one place for interval, lag window and horizon
    data_prep.py  raw logs -> clean fixed-interval grid -> lag-feature dataset
"""
