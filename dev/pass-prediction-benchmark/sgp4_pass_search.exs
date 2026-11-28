# Benchmark for #732 (docs/pass-prediction-design.md): packages/sgp4's pass search over a
# synthetic LEO fleet and 15 stations, one Sgp4.Passes.search/5 per spacecraft.
#
# Usage: elixir dev/pass-prediction-benchmark/sgp4_pass_search.exs [spacecraft] [days] [step_s] [concurrency]
# Defaults: 500 spacecraft, 7 days, 60 s coarse step, all schedulers.
Mix.install([{:sgp4, path: Path.expand("../../packages/sgp4", __DIR__)}])

# Missing trailing arguments take their defaults.
[n, days, step_s, conc] =
  System.argv()
  |> Enum.map(&String.to_integer/1)
  |> Enum.concat([500, 7, 60, System.schedulers_online()] |> Enum.drop(length(System.argv())))

# JD 2461370.5, the prototype's epoch.
epoch = DateTime.from_unix!(round((2_461_370.5 - 2_440_587.5) * 86_400))
re = 6378.135
xke = 60.0 / :math.sqrt(re ** 3 / 398_600.8)

fleet =
  for i <- 0..(n - 1) do
    alt = 500.0 + rem(i * 37, 100)
    # Kozai mean motion from the semi-major axis (earth radii), as rev/day.
    no_kozai = xke / :math.pow((re + alt) / re, 1.5)

    %{
      epoch: epoch,
      mean_motion: no_kozai * 1440.0 / (2 * :math.pi()),
      eccentricity: 0.0005 + rem(i, 10) * 0.0001,
      inclination_deg: if(rem(i, 2) == 0, do: 53.0, else: 97.6),
      raan_deg: rem(i * 13, 360) * 1.0,
      arg_perigee_deg: rem(i * 7, 360) * 1.0,
      mean_anomaly_deg: rem(i * 29, 360) * 1.0,
      bstar: 2.0e-5
    }
  end

stations =
  [
    {64.8, -147.7},
    {78.2, 15.4},
    {-72.0, 2.5},
    {35.4, -116.9},
    {40.4, -4.2},
    {-35.4, 149.0},
    {13.6, 144.9},
    {-25.9, 27.7},
    {19.0, -155.7},
    {67.9, 21.1},
    {-53.0, -70.9},
    {1.4, 103.8},
    {51.1, -114.0},
    {-33.1, -70.7},
    {33.0, 131.0}
  ]
  |> Enum.with_index()
  |> Enum.map(fn {{lat, lon}, i} ->
    {:ok, station} = Sgp4.Station.new(i, lat, lon, 100.0, 5.0)
    station
  end)

to = DateTime.add(epoch, days * 86_400)

{us, results} =
  :timer.tc(fn ->
    fleet
    |> Task.async_stream(
      fn e ->
        {:ok, sat} = Sgp4.init(e)
        {:ok, result} = Sgp4.Passes.search(sat, stations, epoch, to, step_s: step_s)
        result
      end,
      max_concurrency: conc,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end)

passes = results |> Enum.map(&length(&1.passes)) |> Enum.sum()
calls = results |> Enum.map(& &1.propagations) |> Enum.sum()
unbracketed = results |> Enum.map(&length(&1.unbracketed)) |> Enum.sum()
if unbracketed > 0, do: raise("#{unbracketed} passes found no horizon crossing within the bound")
coarse = n * (ceil(days * 86_400 / step_s) + 1)

IO.puts(
  "elixir n=#{n} days=#{days} step=#{step_s}s conc=#{conc} stations=15: #{Float.round(us / 1.0e6, 2)} s, passes=#{passes}, sgp4 calls=#{calls} (coarse #{coarse}, refine #{calls - coarse}), otp=#{System.otp_release()}"
)
