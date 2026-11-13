# AquaSense Dashboard

One web page that brings every AquaSense component together:

| Tab | Source | What it shows |
|---|---|---|
| Overview | all | KPIs, component status, tanks that need attention |
| Feeding | Spring Boot backend | tanks, fish count, appetite (HIGH/LOW + confidence), device health, latest feeding session, last/next feed |
| Water quality | `water_quality/controller` API | live parameters vs safe range, history chart, actuators, alerts |
| Disease checks | backend | saved photo/video white-spot checks, results by label |
| Export planning | backend | saved transit/packing plans and survival verdicts |

No build step and no dependencies: plain HTML/JS plus a tiny Python proxy.

## Try it now (demo data)

```bash
python3 dashboard/serve.py        # http://127.0.0.1:8090
```

It opens in **demo mode** with sample data so you can see the layout.

## Connect the real components

1. Start the backend (`:8080`) and the water-quality controller (`:8000`, see `water_quality/controller/README.md`).
2. Run `python3 dashboard/serve.py`. It serves the page and forwards `/proxy/backend/*` and `/proxy/water/*` to the
   components, so the browser needs no CORS (the backend sends no CORS headers).
   Override the targets with `AQUASENSE_BACKEND_URL` and `AQUASENSE_WATER_URL`.
3. Open **Settings**, choose *Live via serve.py proxy*, paste the backend **access token** (the app JWT returned by
   sign-in), and save. The page refreshes every 15 seconds.

The token is stored only in your browser (`localStorage`) and sent to the backend as a `Bearer` token.

## Notes

- The dashboard is read-only: it does not change tanks, schedules or actuators.
- "Direct URLs" mode calls the servers straight from the browser and only works if they allow CORS.
- The vision pipeline (YOLOv8 + ByteTrack + Random Forest) has no HTTP API of its own; its output appears through the
  backend's appetite observations.
- Water-quality data needs the controller running with a simulator or the ESP32 sending readings.
