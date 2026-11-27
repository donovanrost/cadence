defmodule Cadence.Dev.ReflectOrbital.Fixture do
  @moduledoc "Synthetic interview fixture; these are not Reflect Orbital flight parameters."

  def organization_id, do: "org-reflect-orbital-demo"
  def mission_id, do: "mission-earendil-demo"
  def profile_id, do: "profile-earendil-block-1"
  def provider_id, do: "provider-earendil-demo"
  def account_id, do: "account-earendil-demo"
  def grant_id, do: "grant-earendil-demo"
  def credential_ref, do: "credential-earendil-demo"
  def scenario_id, do: "scenario-earendil-demo-v1"
  def run_id, do: "run-earendil-demo-v1"
  def service_id, do: "service-realtime-ttc-downlink"
  # The simulator's built-in uplink TT&C service and its TC frame size (#44).
  def uplink_service_id, do: "service-realtime-ttc-uplink"
  def tc_frame_size, do: 32
  def frame_size, do: 1115

  def database_path,
    do:
      System.get_env("EARENDIL_DATABASE_PATH") ||
        Path.expand("../../dev/catalogs/demo_spacecraft.yaml", __DIR__)

  def chaos_lab? do
    System.get_env("CADENCE_CHAOS_LAB") == "true" and
      System.get_env("POD_NAMESPACE") == "cadence-chaos"
  end

  def provider_url, do: System.get_env("EARENDIL_PROVIDER_URL", "http://127.0.0.1:4101")
  def ingress_host, do: System.get_env("EARENDIL_INGRESS_HOST", "127.0.0.1")
  def bind_host, do: System.get_env("EARENDIL_BIND_HOST", "127.0.0.1")

  def metadata, do: %{"synthetic" => true, "fixture" => "reflect-orbital-v1"}

  # Fleet size and site count are parameters so every Head measures the same fleet at 500 and
  # 1,000 (#715). SCIDs are the craft index, and the simulator accepts 0..1023.
  @max_spacecraft 1_023
  @spacecraft_per_plane 25

  def fleet_size do
    "EARENDIL_SPACECRAFT_COUNT" |> System.get_env("500") |> bounded!(1, @max_spacecraft)
  end

  def plane_count, do: div(fleet_size() + @spacecraft_per_plane - 1, @spacecraft_per_plane)

  defp bounded!(value, min, max) do
    case Integer.parse(value) do
      {n, ""} when n in min..max//1 ->
        n

      _other ->
        raise ArgumentError, "expected an integer in #{min}..#{max}, got #{inspect(value)}"
    end
  end

  # The simulator names craft PREFIX-<index padded to max(3, digits(count))>; match it.
  defp spacecraft_name(index, width),
    do: "EARENDIL-" <> (index |> Integer.to_string() |> String.pad_leading(width, "0"))

  def spacecraft(count \\ fleet_size()) do
    width = max(3, count |> Integer.to_string() |> String.length())
    commissioning_from = count - div(count, 20)

    Enum.map(1..count, fn index ->
      plane = div(index - 1, @spacecraft_per_plane)
      slot = rem(index - 1, @spacecraft_per_plane)
      name = spacecraft_name(index, width)

      %{
        spacecraft_id: "spacecraft-#{String.downcase(name)}",
        mission_id: mission_id(),
        display_name: name,
        scid: index,
        spacecraft_type_id: profile_id(),
        spacecraft_type_version: 1,
        metadata:
          Map.merge(metadata(), %{
            "serial_number" => "RO-DEMO-#{1000 + index}",
            "block" => "Block 1 demonstration bus",
            "operational_phase" =>
              if(index <= commissioning_from, do: "routine", else: "commissioning"),
            "plane" => plane + 1,
            "slot" => slot + 1,
            "orbit" => %{
              "model" => "synthetic near-polar LEO; not propagated",
              "altitude_km" => 625.0,
              "inclination_deg" => 97.9,
              "eccentricity" => 0.001,
              "raan_deg" => plane * 18.0,
              "mean_anomaly_deg" => Float.round(slot * 14.4 + plane * 0.72, 2),
              "epoch" => "2026-10-19T00:00:00Z"
            },
            "payload" => %{
              "type" => "steerable solar reflector",
              "deployment_state" =>
                if(index <= commissioning_from, do: "deployed", else: "stowed"),
              "illumination_enabled" => false
            },
            "radio" => %{
              "ttc_band" => "S",
              "downlink_bps" => 1_000_000,
              "uplink_bps" => 64_000,
              "virtual_channel" => 0
            },
            "flight_software" => "earendil-demo-1.0.0"
          })
      }
    end)
  end

  # Short station codes for console rows (ground_station `code`, ^[A-Z0-9]{2,8}$).
  @station_codes %{
    "earendil-svalbard" => "SVA",
    "earendil-troll" => "TRL",
    "earendil-fairbanks" => "FAI",
    "earendil-kiruna" => "KIR",
    "earendil-hawaii" => "HAW",
    "earendil-santiago" => "SCL",
    "earendil-punta-arenas" => "PUQ",
    "earendil-hartebeesthoek" => "HBK",
    "earendil-perth" => "PER",
    "earendil-invercargill" => "INV",
    "earendil-singapore" => "SIN",
    "earendil-mauritius" => "MRU",
    "earendil-azores" => "AZO",
    "earendil-dubai" => "DXB",
    "earendil-alice-springs" => "ASP"
  }

  def station_code(site_id), do: Map.fetch!(@station_codes, site_id)

  @sites [
    {"svalbard", "Svalbard", "Norway / Arctic", 78.23, 15.41, 6},
    {"troll", "Troll", "Antarctica", -72.01, 2.54, 4},
    {"fairbanks", "Fairbanks", "Alaska / North America", 64.84, -147.72, 4},
    {"kiruna", "Kiruna", "Sweden / Europe", 67.86, 20.23, 4},
    {"hawaii", "Hawaii", "Pacific / North America", 19.82, -155.47, 3},
    {"santiago", "Santiago", "Chile / South America", -33.45, -70.67, 3},
    {"punta-arenas", "Punta Arenas", "Chile / Southern hemisphere", -53.16, -70.91, 4},
    {"hartebeesthoek", "Hartebeesthoek", "South Africa", -25.89, 27.69, 3},
    {"perth", "Perth", "Australia / Indian Ocean", -31.95, 115.86, 3},
    {"invercargill", "Invercargill", "New Zealand / South Pacific", -46.41, 168.35, 4},
    {"singapore", "Singapore", "Southeast Asia", 1.35, 103.82, 3},
    {"mauritius", "Mauritius", "Indian Ocean", -20.16, 57.5, 3},
    {"azores", "Azores", "North Atlantic", 37.74, -25.67, 3},
    {"dubai", "Dubai", "Middle East", 25.2, 55.27, 3},
    {"alice-springs", "Alice Springs", "Australia / Interior", -23.7, 133.88, 3}
  ]

  def site_count do
    # At least two: a craft's candidate site must differ from its primary. Default 10, the demo and
    # console e2e set; the scale harness runs 15.
    "EARENDIL_SITE_COUNT" |> System.get_env("10") |> bounded!(2, length(@sites))
  end

  def sites do
    @sites
    |> Enum.take(site_count())
    |> Enum.with_index()
    |> Enum.map(fn {{id, name, region, latitude, longitude, antennas}, index} ->
      %{
        "id" => "earendil-#{id}",
        "name" => "#{name} (Demo)",
        "region" => region,
        # Reported in the provider inventory as the station's location (#957).
        "location" => %{"latitude_deg" => latitude, "longitude_deg" => longitude},
        "antenna_count" => antennas,
        "ingress_port" =>
          String.to_integer(System.get_env("EARENDIL_INGRESS_BASE_PORT", "42100")) + index,
        "uplink_port" =>
          String.to_integer(System.get_env("EARENDIL_UPLINK_BASE_PORT", "42200")) + index,
        "synthetic" => true
      }
    end)
  end

  def scenario do
    fleet = spacecraft()

    %{
      "id" => scenario_id(),
      "name" => "Earendil — #{length(fleet)}-spacecraft rehearsal",
      "description" => "Synthetic fleet and ground sites for a Cadence interview demonstration.",
      "spacecraft_count" => length(fleet),
      "spacecraft_prefix" => "EARENDIL",
      "ground_stations" => sites(),
      "orbit_readiness" => %{
        "status" => "current",
        "source_kind" => "synthetic",
        "ephemeris_ref" => "earendil-demo-orbits-v1",
        "version" => 1,
        "validity_seconds" => 604_800
      },
      "pass_model" => %{
        "cadence_seconds" => 5_820,
        "duration_seconds" => 480,
        "jitter_seconds" => 120
      },
      "telemetry_profile" => %{
        "rate_hz" => 1.0,
        "noise_amplitude" => 0.05,
        "spacecraft_frames" =>
          Map.new(fleet, &{&1.display_name, %{"scid" => &1.scid, "vcid" => 0}})
      },
      "fault_profile" => %{}
    }
  end

  # Cadence listens on the site's uplink port; the provider connects, takes TC frames and
  # answers with CLCWs (#44).
  def uplink_delivery(site) do
    %{
      "display_name" => "Cadence → #{site["name"]} uplink",
      "client_reference" => "#{site["id"]}:uplink",
      "direction" => "uplink",
      "delivery_kind" => "realtime_stream",
      "target" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => ingress_host(),
        "port" => site["uplink_port"]
      },
      "framing" => %{
        "family" => "ccsds_tc",
        "mode" => "fixed_size",
        "frame_bytes" => tc_frame_size()
      }
    }
  end

  def delivery(site) do
    %{
      "display_name" => "#{site["name"]} → Cadence",
      "client_reference" => site["id"],
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "target" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => ingress_host(),
        "port" => site["ingress_port"]
      },
      "framing" => %{
        "family" => "ccsds_tm",
        "mode" => "fixed_size",
        "frame_bytes" => frame_size()
      }
    }
  end
end
