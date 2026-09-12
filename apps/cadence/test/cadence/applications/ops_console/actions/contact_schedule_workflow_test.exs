defmodule Cadence.Applications.OpsConsole.Actions.ContactScheduleWorkflowTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{ActionDispatcher, ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Applications.OpsConsole.ActionProvider
  alias Cadence.ContactPlanning.OpportunityCapability
  alias Cadence.Contacts.{ProviderReservations, ProviderScheduling}
  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactSchedule
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    defaults = Req.default_options()
    local = Application.get_env(:cadence, :provider_local_credentials)
    credentials = Application.get_env(:cadence, :ground_network_credentials)
    Req.default_options(adapter: __MODULE__, retry: false)
    Application.put_env(:cadence, :provider_local_credentials, enabled: true)

    Application.put_env(:cadence, :ground_network_credentials, %{
      "simulator" => "test-only-secret"
    })

    on_exit(fn ->
      Req.default_options(defaults)
      restore(:provider_local_credentials, local)
      restore(:ground_network_credentials, credentials)
    end)

    Fixtures.setup_schedule()
  end

  test "real search, sealed reservation and reviewed cancellation preserve durable identities",
       c do
    {:ok, %{schedule: model}} =
      ContactSchedule.load(c.scope, c.mission, %{"spacecraft_id" => c.spacecraft.spacecraft_id})

    search_payload = native(model, "search")
    form = search_payload["contact_search"]
    {:ok, start, _} = DateTime.from_iso8601(form["starts_at"])

    opportunity =
      Fixtures.opportunity(c.route, start)
      |> Map.put("extensions", %{"cost" => 25, "private" => "never-public"})

    test_pid = self()

    Process.put(:schedule_request_handler, fn conn ->
      send(test_pid, {:http, conn.method, conn.url.path})

      case conn.url.path do
        "/provider/v1/opportunities/search" ->
          response(conn, %{"data" => [opportunity], "meta" => %{}})

        "/provider/v1/capabilities" ->
          {:ok, caps} = FakeProviderClient.capabilities(nil, [])
          response(conn, %{"data" => caps.evidence})

        "/provider/v1/contacts" ->
          attrs = conn.body |> IO.iodata_to_binary() |> Jason.decode!()
          response = contact(opportunity, attrs["client_reference"], "confirmed", 1)
          Process.put(:schedule_provider_contact, response)
          response(conn, %{"data" => response})

        "/provider/v1/contacts/provider-contact-one/cancel" ->
          response =
            Process.get(:schedule_provider_contact)
            |> Map.merge(%{"status" => "canceled", "revision" => 2})

          response(conn, %{"data" => response})
      end
    end)

    assert {:ok, found} = execute(c, "search", search_payload)
    assert ActionDispatcher.result("ops_console", found) == found
    assert [o] = found["opportunities"]
    assert o["cost"] == 25
    {:ok, expires, _} = DateTime.from_iso8601(o["expires_at"])
    assert DateTime.diff(expires, DateTime.utc_now()) in 0..900
    refute Jason.encode!(found) =~ "never-public"
    assert {:ok, payload} = OpportunityCapability.verify(o["token"])
    refute Map.has_key?(payload["opportunity"], "extensions")
    assert {:ok, first} = execute(c, "reserve", native(model, "reserve", found))
    assert first["lifecycleState"] == "confirmed"
    assert {:ok, ^first} = execute(c, "reserve", %{"token" => o["token"]})
    assert_receive {:http, :post, "/provider/v1/contacts"}
    refute_receive {:http, :post, "/provider/v1/contacts"}

    {:ok, r} =
      ProviderReservations.fetch(c.organization_id, c.mission_id, first["providerReservationId"])

    {:ok, %{schedule: refreshed}} =
      ContactSchedule.load(c.scope, c.mission, %{"spacecraft_id" => c.spacecraft.spacecraft_id})

    assert {:ok, canceled} = execute(c, "cancel", native(refreshed, "cancel"))
    assert canceled["lifecycleState"] == "canceled"
    assert canceled["providerReservationId"] == first["providerReservationId"]
    assert canceled["scheduledContactId"] == first["scheduledContactId"]

    assert {:error, :stale_reservation_cancellation_evidence} =
             execute(c, "cancel", %{"reservation_evidence" => evidence(c, r)})

    assert_receive {:http, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
    refute_receive {:http, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
  end

  test "stale route evidence and expired capabilities fail before provider traffic", c do
    Process.put(:schedule_request_handler, fn _ ->
      flunk("stale evidence reached the provider")
    end)

    start = DateTime.utc_now() |> DateTime.add(900) |> DateTime.truncate(:second)

    form = %{
      "spacecraft_id" => c.spacecraft.spacecraft_id,
      "route_key" => c.route.route_key,
      "starts_at" => DateTime.to_iso8601(start),
      "ends_at" => DateTime.to_iso8601(DateTime.add(start, 3600))
    }

    pins = ProviderScheduling.route_evidence(c.route)

    assert {:error, :route_changed} =
             execute(c, "search", %{
               "contact_search" => form,
               "route_evidence" => Map.put(pins, "transport_version", 999)
             })

    payload = %{
      "organization_id" => c.organization_id,
      "mission_id" => c.mission_id,
      "spacecraft_id" => c.spacecraft.spacecraft_id,
      "route_key" => c.route.route_key,
      "route" => pins,
      "opportunity" => Fixtures.opportunity(c.route, start)
    }

    for value <- ["2020-01-01T00:00:00Z", nil, 12] do
      token =
        payload |> put_in(["opportunity", "expires_at"], value) |> OpportunityCapability.sign()

      assert {:error, :opportunity_expired_or_unavailable} =
               execute(c, "reserve", %{"token" => token})
    end
  end

  test "large provider search stays within the host document boundary with explicit truncation",
       c do
    {:ok, %{schedule: model}} =
      ContactSchedule.load(c.scope, c.mission, %{"spacecraft_id" => c.spacecraft.spacecraft_id})

    form = %{
      "spacecraft_id" => c.spacecraft.spacecraft_id,
      "route_key" => c.route.route_key,
      "starts_at" => model.initial_window.starts_at,
      "ends_at" => model.initial_window.ends_at
    }

    {:ok, start, _} = DateTime.from_iso8601(form["starts_at"])

    rows =
      Enum.map(1..100, fn n ->
        Fixtures.opportunity(c.route, start) |> Map.put("id", "opportunity-#{n}")
      end)

    Process.put(:schedule_request_handler, fn request ->
      response(request, %{"data" => rows, "meta" => %{}})
    end)

    assert {:ok, found} =
             execute(c, "search", %{
               "contact_search" => form,
               "route_evidence" => ProviderScheduling.route_evidence(c.route)
             })

    assert found["truncated"]
    assert length(found["opportunities"]) in 1..99
    assert byte_size(Jason.encode!(found)) <= 60_000

    assert {:ok, _} =
             JSONBoundary.safe_trusted_output(%{
               "receiptId" => "receipt",
               "completedAt" => DateTime.to_iso8601(DateTime.utc_now()),
               "result" => found
             })

    assert ActionDispatcher.result("ops_console", found) == found
  end

  test "cancellation rejects extra input, mismatched scope and unknown state", c do
    for e <- [%{}, %{"contract_version" => 1, "organization_id" => "foreign"}] do
      assert {:error, :invalid_reservation_cancellation_evidence} =
               execute(c, "cancel", %{"reservation_evidence" => e})
    end
  end

  @native Path.expand(
            "../../../../../../../frontend/modules/planning-and-contacts/src/features/contact-scheduling/schedule-producer-check.mjs",
            __DIR__
          )
  defp native(model, action, result \\ nil) do
    {output, status} =
      System.cmd("node", [@native, Jason.encode!(model), action, Jason.encode!(result)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    [_, payload] = Regex.run(~r/SCHEDULE_PAYLOAD=(.*)/, output)
    Jason.decode!(payload)
  end

  def run(request), do: Process.get(:schedule_request_handler).(request)
  defp response(request, data), do: {request, %Req.Response{status: 200, body: data}}

  defp execute(c, action, params),
    do:
      ActionProvider.execute(
        c.scope,
        HostContext.mission(c.mission_id),
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          surface_id: "contact_schedule",
          surface_version: 1,
          action_id: action,
          params: params
        }
      )

  defp evidence(c, r),
    do: %{
      "contract_version" => 1,
      "organization_id" => c.organization_id,
      "mission_id" => c.mission_id,
      "reservation_id" => r.provider_reservation_id,
      "provider_revision" => r.provider_revision,
      "lifecycle_state" => to_string(r.lifecycle_state),
      "provider_contact_ref" => r.provider_contact_ref
    }

  defp contact(o, client, status, revision),
    do:
      o
      |> Map.drop(["availability", "expires_at", "synthetic"])
      |> Map.merge(%{
        "id" => "provider-contact-one",
        "provider_contact_ref" => "provider-contact-one",
        "opportunity_ref" => o["id"],
        "delivery_profile_ref" => "delivery-cadence",
        "client_reference" => client,
        "status" => status,
        "revision" => revision,
        "pass_phase" => "scheduled",
        "delivery" => %{
          "status" => "pending",
          "direction" => "downlink",
          "delivery_kind" => "realtime_stream",
          "mode" => "provider_connects",
          "protocol" => "tcp",
          "endpoint_ref" => "delivery-cadence",
          "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
          "allowed_source_refs" => [o["spacecraft_ref"]],
          "activation_window" => Map.take(o, ~w(starts_at ends_at)),
          "credential_ref" => nil,
          "diagnostics" => %{},
          "reason" => nil
        },
        "tags" => %{},
        "status_reason" => nil
      })

  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)
end
