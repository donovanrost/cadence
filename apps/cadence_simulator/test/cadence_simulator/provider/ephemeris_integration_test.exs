defmodule CadenceSimulator.Provider.EphemerisIntegrationTest do
  @moduledoc """
  An element set reaches the simulator through Provider Contract v1 (#968): Cadence's
  `SimulatorHTTP` client reads the provider's capabilities, uploads the set as an OMM, and an
  opportunity search on a scenario that reads orbits from uploads is then ready.
  """
  use CadenceSimulator.Case, async: false

  @moduletag :integration
  @moduletag :config

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks.{ElementSet, ProviderContext, ProviderError}
  alias Cadence.GroundNetworks.ElementSets.OmmDocument
  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Router, Store}

  @router_options [
    provider_auth: [
      provider_admin_api_token: "admin-secret",
      provider_api_token: "provider-secret"
    ]
  ]

  setup do
    :ok = Store.clear()
    port = free_port()

    start_supervised!(
      {Bandit, plug: {Router, @router_options}, scheme: :http, ip: {127, 0, 0, 1}, port: port}
    )

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "orbit_readiness" => %{"source_kind" => "uploaded"}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 968})
    %{context: provider_context("http://127.0.0.1:#{port}", run["id"])}
  end

  test "Cadence uploads the current set and the provider is then ready for it", c do
    epoch = DateTime.utc_now() |> DateTime.add(-3_600) |> DateTime.truncate(:microsecond)
    set = element_set(epoch)

    ephemeris = %{
      "omm" => OmmDocument.from_element_set(set),
      "epoch" => DateTime.to_iso8601(epoch),
      "content_sha256" => set.content_sha256
    }

    params = search_params(["SC-001"])

    assert {:error, %ProviderError{}} =
             SimulatorHTTP.search_opportunities(c.context, params, opts())

    assert {:ok, %{"spacecraft_ref" => "SC-001", "content_sha256" => sha}} =
             SimulatorHTTP.upload_ephemeris(c.context, "SC-001", ephemeris, opts())

    assert sha == set.content_sha256

    # Idempotent per content hash.
    assert {:ok, %{"content_sha256" => ^sha}} =
             SimulatorHTTP.upload_ephemeris(c.context, "SC-001", ephemeris, opts())

    assert {:ok, page} = SimulatorHTTP.search_opportunities(c.context, params, opts())

    assert %{"status" => "current", "source_kind" => "uploaded", "ephemeris_ref" => ^sha} =
             page.provider_evidence["orbit_readiness"]
  end

  test "after the upload, Cadence's search returns the orbit's real passes with geometry (#893)",
       c do
    epoch = DateTime.utc_now() |> DateTime.add(-3_600) |> DateTime.truncate(:microsecond)
    set = element_set(epoch)

    ephemeris = %{
      "omm" => OmmDocument.from_element_set(set),
      "epoch" => DateTime.to_iso8601(epoch),
      "content_sha256" => set.content_sha256
    }

    assert {:ok, _stored} = SimulatorHTTP.upload_ephemeris(c.context, "SC-001", ephemeris, opts())

    day = search_params(["SC-001"], 86_400) |> Map.put("page_size", 50)

    assert {:ok, %{data: [_ | _] = offers}} =
             SimulatorHTTP.search_opportunities(c.context, day, opts())

    for offer <- offers do
      assert %{"model" => "sgp4_pass_v1", "max_elevation_deg" => elevation, "tca" => tca} =
               offer.extensions

      assert elevation >= 5.0 and elevation <= 90.0
      {:ok, tca, 0} = DateTime.from_iso8601(tca)

      assert DateTime.after?(tca, at(offer.starts_at)) and
               DateTime.before?(tca, at(offer.ends_at))
    end
  end

  defp element_set(epoch) do
    %ElementSet{
      element_set_id: "elset-integration",
      organization_id: "organization-integration",
      mission_id: "mission-integration",
      spacecraft_id: "spacecraft-integration",
      object_name: "SC 1",
      norad_id: 90_001,
      epoch: epoch,
      mean_motion: 15.2,
      eccentricity: 0.0005,
      inclination_deg: 53.0,
      raan_deg: 10.0,
      arg_perigee_deg: 20.0,
      mean_anomaly_deg: 30.0,
      bstar: 2.0e-5,
      mean_motion_dot: 0.0,
      mean_motion_ddot: 0.0,
      content_sha256: :sha256 |> :crypto.hash("sc-1-#{epoch}") |> Base.encode16(case: :lower)
    }
  end

  defp search_params(refs, seconds \\ 180) do
    starts_at = DateTime.utc_now() |> DateTime.add(30) |> DateTime.truncate(:second)

    %{
      "spacecraft_refs" => refs,
      "ground_station_refs" => [],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(seconds) |> DateTime.to_iso8601(),
      "page_size" => 10,
      "cursor" => nil
    }
  end

  defp at(%DateTime{} = at), do: at

  defp at(iso) when is_binary(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    at
  end

  defp opts, do: [credential_resolver: &resolve_credential/1]

  defp provider_context(base_url, environment_ref) do
    {:ok, context} =
      ProviderContext.new(%{
        provider_ref: "simulator-integration",
        organization_id: "organization-integration",
        mission_id: "mission-integration",
        client_key: "simulator_http",
        base_url: base_url,
        credential_ref: "test-provider-token",
        environment_ref: environment_ref
      })

    context
  end

  defp resolve_credential("test-provider-token"), do: {:ok, "provider-secret"}

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
