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
  def frame_size, do: 1115

  def database_path,
    do: Path.expand("../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml", __DIR__)

  def metadata, do: %{"synthetic" => true, "fixture" => "reflect-orbital-v1"}

  def spacecraft do
    Enum.map(1..500, fn index ->
      plane = div(index - 1, 25)
      slot = rem(index - 1, 25)
      name = "EARENDIL-#{String.pad_leading(Integer.to_string(index), 3, "0")}"

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
            "operational_phase" => if(index <= 475, do: "routine", else: "commissioning"),
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
              "deployment_state" => if(index <= 475, do: "deployed", else: "stowed"),
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

  def sites do
    [
      {"svalbard", "Svalbard", "Norway / Arctic", 78.23, 15.41, 6},
      {"troll", "Troll", "Antarctica", -72.01, 2.54, 4},
      {"fairbanks", "Fairbanks", "Alaska / North America", 64.84, -147.72, 4},
      {"kiruna", "Kiruna", "Sweden / Europe", 67.86, 20.23, 4},
      {"hawaii", "Hawaii", "Pacific / North America", 19.82, -155.47, 3},
      {"santiago", "Santiago", "Chile / South America", -33.45, -70.67, 3},
      {"punta-arenas", "Punta Arenas", "Chile / Southern hemisphere", -53.16, -70.91, 4},
      {"hartebeesthoek", "Hartebeesthoek", "South Africa", -25.89, 27.69, 3},
      {"perth", "Perth", "Australia / Indian Ocean", -31.95, 115.86, 3},
      {"invercargill", "Invercargill", "New Zealand / South Pacific", -46.41, 168.35, 4}
    ]
    |> Enum.with_index()
    |> Enum.map(fn {{id, name, region, latitude, longitude, antennas}, index} ->
      %{
        "id" => "earendil-#{id}",
        "name" => "#{name} (Demo)",
        "region" => region,
        "latitude_deg" => latitude,
        "longitude_deg" => longitude,
        "antenna_count" => antennas,
        "ingress_port" => 42_100 + index,
        "synthetic" => true
      }
    end)
  end

  def scenario do
    %{
      "id" => scenario_id(),
      "name" => "Earendil — 500-spacecraft rehearsal",
      "description" => "Synthetic fleet and ground sites for a Cadence interview demonstration.",
      "spacecraft_count" => 500,
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
          Map.new(spacecraft(), &{&1.display_name, %{"scid" => &1.scid, "vcid" => 0}})
      },
      "fault_profile" => %{}
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
        "host" => "127.0.0.1",
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
