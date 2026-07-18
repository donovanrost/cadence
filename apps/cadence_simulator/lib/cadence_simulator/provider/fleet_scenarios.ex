defmodule CadenceSimulator.Provider.FleetScenarios do
  @moduledoc """
  Built-in deterministic scenario documents for mission-scale qualification.

  These documents are simulator administration inputs. Cadence only observes the
  resulting provider inventory, opportunities, lifecycle responses, events, and
  telemetry.
  """

  @service_profile_ref "service-realtime-ttc-downlink"

  @spec stage_five(keyword()) :: map()
  def stage_five(opts \\ []) do
    spacecraft_count = Keyword.get(opts, :spacecraft_count, 300)

    %{
      "name" => "Stage 5 fleet planning and chaos qualification",
      "description" =>
        "Several-hundred-spacecraft provider scenario with exclusive pools and bounded faults.",
      "spacecraft_count" => spacecraft_count,
      "spacecraft_prefix" => "SC",
      "ground_stations" => [
        station("station-svalbard", "Svalbard", "arctic"),
        station("station-troll", "Troll", "antarctic"),
        station("station-hawaii", "Hawaii", "pacific")
      ],
      "route_profiles" => [
        route_profile(
          "route-svalbard-shared",
          "station-svalbard",
          "pool-svalbard-realtime",
          15,
          1
        ),
        route_profile(
          "route-troll-shared",
          "station-troll",
          "pool-troll-realtime",
          5,
          0
        ),
        route_profile(
          "route-hawaii-shared",
          "station-hawaii",
          "pool-hawaii-realtime",
          0,
          0
        )
      ],
      "provider_behavior" => %{
        "confirmation" => "asynchronous",
        "idempotency" => "client_reference",
        "recovery" => "client_reference",
        "event_delivery_semantics" => "at_least_once",
        "spacecraft_batch_limit" => 100,
        "station_batch_limit" => 30,
        "page_size_limit" => 100
      },
      "orbit_readiness" => %{
        "status" => "current",
        "source_kind" => "synthetic",
        "ephemeris_ref" => "stage-five-synthetic-oem",
        "version" => 5,
        "validity_seconds" => 86_400
      },
      "pass_model" => %{
        "cadence_seconds" => 900,
        "duration_seconds" => 600,
        "jitter_seconds" => 45
      },
      "telemetry_profile" => %{
        "rate_hz" => 5.0
      },
      "fault_profile" => %{
        "scheduling_rejection_rate" => 0.15,
        "contact_response_loss_after_commit_count" => 1,
        "event_duplication_count" => 1,
        "event_delay_poll_count" => 1
      }
    }
  end

  defp station(id, name, region) do
    %{
      "id" => id,
      "name" => name,
      "region" => region,
      "antenna_count" => 10
    }
  end

  defp route_profile(id, station_ref, pool_ref, latency_ms, rate_limit_count) do
    %{
      "id" => id,
      "ground_station_ref" => station_ref,
      "service_profile_ref" => @service_profile_ref,
      "antenna_or_service_pool_ref" => pool_ref,
      "request_latency_ms" => latency_ms,
      "rate_limit_response_count" => rate_limit_count,
      "retry_after_seconds" => 1,
      "opportunity_expiry_offset_seconds" => -120
    }
  end
end
