# SGP4

Dependency-free near-earth SGP4 in Elixir, with WGS84 station geometry and a pass search. It is
slice 2 of #732; the design is `docs/pass-prediction-design.md` (DECISIONS #114).

```elixir
{:ok, sat} = Sgp4.init(elements)
{:ok, position_km, velocity_km_s} = Sgp4.propagate(sat, minutes_since_epoch)

{:ok, station} = Sgp4.Station.new("svalbard", 78.23, 15.39, 450.0, 5.0)
{:ok, %{passes: passes, unbracketed: [], propagations: _}} =
  Sgp4.Passes.search(sat, [station], from, to)
```

## Scope

- **SGP4:** a port of Vallado's 2006 reference implementation (AIAA 2006-6753), near-earth
  branch, WGS72 constants, improved mode. Input is mean elements as TLEs and OMMs carry them:
  `epoch`, `mean_motion` (rev/day, Kozai), `eccentricity`, `inclination_deg`, `raan_deg`,
  `arg_perigee_deg`, `mean_anomaly_deg` and `bstar`. Output is position (km) and velocity (km/s)
  in TEME.
- **Frames:** TEME → earth-fixed by GMST (IAU-82). UT1 is taken as UTC and polar motion is
  ignored, both far below SGP4's own error.
- **Stations:** WGS84 geodetic latitude, longitude and height, plus an elevation mask.
- **Passes:** a 60 s coarse grid shared by all stations; AOS and LOS by bisection, TCA by golden
  section, each to 1 s; maximum elevation and azimuth at AOS and LOS. A pass that overlaps the
  window is found whole, with the search past each end bounded by the synodic period. A pass with
  no crossing inside that bound is never given a clipped time: `search/5` still returns
  `{:ok, %{passes: [...], unbracketed: [...], propagations: n}}`, and each such pass appears in
  `unbracketed` as `{:error, :pass_not_bracketed, %{station_id: id, near: datetime}}`.

## Accuracy

Vallado's full verification set (`test/fixtures`, from CelesTrak's AIAA 2006-6753 archive) runs
in the tests. Every near-earth case matches the reference at every reference time within
0.007 mm in position and 1e-9 km/s in velocity, which is the reference's printed precision.
SGP4's own error dominates in use: about 1 km at epoch, growing a few km per day.

AOS and LOS are within 1 s of the mask crossing for the given elements. A pass shorter than the
coarse step can fall between two grid points and be missed: at 60 s, that is a grazing pass
shorter than any schedulable contact.

## What it refuses

- `:deep_space_not_supported`: a period of 225 minutes or more (SDP4 is a later slice). The
  verification set's 24 deep-space cases are all refused.
- `:mean_elements_out_of_range` (Vallado's code 1), `:mean_motion_not_positive` (2),
  `:semi_latus_rectum_negative` (4) and `:decayed` (6), at initialization or propagation. The
  set's three decaying near-earth cases fail at exactly the step where the reference stops.
- `:latitude_out_of_range`, `:longitude_out_of_range` and `:mask_out_of_range` for a station.
