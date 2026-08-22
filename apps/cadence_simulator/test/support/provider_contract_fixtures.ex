defmodule CadenceSimulator.TestProviderFixtures do
  @moduledoc false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Contacts, DeliveryProfiles, Opportunities}

  def create_contact!(scenario_overrides \\ %{}, opts \\ []) do
    suffix = System.unique_integer([:positive])

    scenario_attrs =
      Map.merge(
        %{
          "spacecraft_count" => 2,
          "provider_behavior" => %{"idempotency" => "native"},
          "pass_model" => %{
            "cadence_seconds" => 600,
            "duration_seconds" => 300,
            "jitter_seconds" => 0
          }
        },
        scenario_overrides
      )

    {:ok, scenario} = Provider.create_scenario(scenario_attrs)

    {:ok, run} =
      Provider.create_run(scenario["id"], %{
        "seed" => 42,
        "state" => Keyword.get(opts, :run_state, "running")
      })

    {:ok, delivery_profile} =
      DeliveryProfiles.provision(run, %{
        "display_name" => "Test telemetry ingress",
        "client_reference" => "test-delivery-#{suffix}",
        "direction" => "downlink",
        "delivery_kind" => "realtime_stream",
        "target" => %{
          "protocol" => "tcp",
          "mode" => "provider_connects",
          "host" => "127.0.0.1",
          "port" => 41_001
        },
        "framing" => %{
          "family" => "ccsds_tm",
          "mode" => "fixed_size",
          "frame_bytes" => 1115
        }
      })

    starts_at = Keyword.get(opts, :search_starts_at, ~U[2026-07-17 12:00:00Z])
    ends_at = DateTime.add(starts_at, 3_600)

    {:ok, %{data: [opportunity | _rest]}} =
      Opportunities.search(run, %{
        "spacecraft_refs" => ["SC-001"],
        "ground_station_refs" => [],
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "starts_at" => DateTime.to_iso8601(starts_at),
        "ends_at" => DateTime.to_iso8601(ends_at),
        "page_size" => 25
      })

    request = %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => Keyword.get(opts, :client_reference, "test-contact-#{suffix}"),
      "tags" => %{}
    }

    {:ok, contact} =
      Contacts.create(run, request,
        idempotency_key: Keyword.get(opts, :idempotency_key, "test-booking-#{suffix}")
      )

    %{
      scenario: scenario,
      run: run,
      opportunity: opportunity,
      delivery_profile: delivery_profile,
      request: request,
      contact: contact
    }
  end
end
