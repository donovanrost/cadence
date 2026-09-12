defmodule CadenceWeb.OpsContactSchedulingPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.GroundNetworks.ProviderContact
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-scheduling/contact-workflow-check.mjs",
              __DIR__
            )
  setup do
    c = Fixtures.setup_schedule()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, c.scope.organization, role: :organization_admin)
    defaults = Req.default_options()
    local = Application.get_env(:cadence, :provider_local_credentials)
    credentials = Application.get_env(:cadence, :ground_network_credentials)
    Application.put_env(:cadence, :provider_local_credentials, enabled: true)

    Application.put_env(:cadence, :ground_network_credentials, %{
      "simulator" => "test-only-secret"
    })

    {:ok, store} = Agent.start_link(fn -> %{contact: nil, fail_booking: false} end)
    test_pid = self()

    :persistent_term.put({__MODULE__, :handler}, fn request ->
      send(test_pid, {:provider, request.method, request.url.path})

      case request.url.path do
        "/provider/v1/capabilities" ->
          {:ok, caps} = FakeProviderClient.capabilities(nil, [])
          provider_response(request, %{"data" => caps.evidence})

        "/provider/v1/opportunities/search" ->
          attrs = request.body |> IO.iodata_to_binary() |> Jason.decode!()
          {:ok, start, _} = DateTime.from_iso8601(attrs["starts_at"])
          opportunity = Fixtures.opportunity(c.route, start)
          Agent.update(store, &Map.put(&1, :opportunity, opportunity))
          provider_response(request, %{"data" => [opportunity], "meta" => %{}})

        "/provider/v1/contacts" ->
          if Agent.get(store, & &1.fail_booking) do
            {request, %Req.TransportError{reason: :timeout}}
          else
            attrs = request.body |> IO.iodata_to_binary() |> Jason.decode!()

            contact =
              contact(
                Agent.get(store, & &1.opportunity),
                attrs["client_reference"],
                "confirmed",
                1
              )

            Agent.update(store, &Map.put(&1, :contact, contact))
            provider_response(request, %{"data" => contact})
          end

        "/provider/v1/contacts/provider-contact-one/cancel" ->
          contact =
            Agent.get(store, & &1.contact)
            |> Map.merge(%{"status" => "canceled", "revision" => 2})

          provider_response(request, %{"data" => contact})
      end
    end)

    Req.default_options(adapter: __MODULE__, retry: false)

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :handler})
      Req.default_options(defaults)
      restore(:provider_local_credentials, local)
      restore(:ground_network_credentials, credentials)
    end)

    Map.merge(c, %{
      user: user,
      conn: TestFixtures.member_conn(user),
      store: store,
      path: "/missions/#{c.mission_id}/ops/contacts?spacecraft_id=#{c.spacecraft.spacecraft_id}"
    })
  end

  test "native search reserve and cancel use actual capabilities and keep durable identities",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.contact-schedule"
    assert original["status"] == "ready"

    assert original["context"] == %{
             "organizationId" => c.organization_id,
             "missionId" => c.mission_id
           }

    Enum.reduce(~w(search reserve cancel), original, fn event, current ->
      [[^event, input]] = native(%{snapshot: current, action: event})
      op = action(view, c.path, original, event, input)["snapshot"]
      assert op["status"] == "completed", inspect(op)
      assert op["receipt"]["result"]["actor_id"] == c.user.user_id
      fresh = read(view, c.path, original)["snapshot"]
      assert fresh["data"]["operation"] == op

      assert [[event, input]] ==
               native(%{snapshot: current, action: event, operation: op, refreshed: fresh})

      assert action(view, c.path, original, event, input)["snapshot"]["status"] == "rejected"

      if event == "search" do
        [o] = fresh["data"]["search"]["opportunities"]
        assert byte_size(o["token"]) > 240
      end

      fresh
    end)

    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
    assert_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
    refute_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
  end

  test "an uncertain booking retains its recorded identity and blocks repeated provider effects",
       c do
    Agent.update(c.store, &Map.put(&1, :fail_booking, true))
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    [[event, input]] = native(%{snapshot: original, action: "search"})
    assert action(view, c.path, original, event, input)["snapshot"]["status"] == "completed"
    searched = read(view, c.path, original)["snapshot"]
    [[event, input]] = native(%{snapshot: searched, action: "reserve"})
    op = action(view, c.path, original, event, input)["snapshot"]
    assert op["status"] == "unconfirmed", inspect(op)
    result = op["receipt"]["result"]["value"]
    assert result["providerRevision"] == 1
    assert result["scheduledContactId"] == nil

    assert {:ok, row} =
             ProviderReservations.fetch(
               c.organization_id,
               c.mission_id,
               result["providerReservationId"]
             )

    assert row.lifecycle_state in [:unknown, :failed]
    assert op["receipt"]["result"]["source"] == "recorded"
    fresh = read(view, c.path, original)["snapshot"]
    assert fresh["status"] == "ready"

    assert [[event, input]] ==
             native(%{snapshot: searched, action: event, operation: op, refreshed: fresh})

    assert action(view, c.path, original, event, %{input | "sequence" => 3})["snapshot"]["status"] ==
             "rejected"

    external = contact(Agent.get(c.store, & &1.opportunity), row.idempotency_key, "confirmed", 2)
    assert {:ok, observed} = ProviderContact.from_external(external)

    assert {:ok, _} =
             ProviderReservations.apply_provider_status(
               c.organization_id,
               c.mission_id,
               row.provider_reservation_id,
               ProviderContact.to_reservation_result(observed)
             )

    recovered = read(view, c.path, original)["snapshot"]
    assert recovered["data"]["operation"]["status"] == "completed"
    assert recovered["data"]["operation"]["receipt"]["result"]["source"] == "observed"

    assert recovered["data"]["operation"]["receipt"]["result"]["value"]["providerReservationId"] ==
             row.provider_reservation_id

    assert [] == native(%{snapshot: recovered})

    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  test "booking reconciliation reads the returned reservation even outside the current ledger page",
       c do
    path = c.path <> "&reservations_page=2"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    [[event, input]] = native(%{snapshot: original, action: "search"})
    assert action(view, path, original, event, input)["snapshot"]["status"] == "completed"
    searched = read(view, path, original)["snapshot"]
    [[event, input]] = native(%{snapshot: searched, action: "reserve"})
    op = action(view, path, original, event, input)["snapshot"]
    assert op["status"] == "completed"
    fresh = read(view, path, original)["snapshot"]
    assert fresh["data"]["model"]["reservations"]["page"] == 2
    assert fresh["data"]["model"]["reservations"]["entries"] == []

    assert fresh["data"]["operation_reservation"]["reservation"]["id"] ==
             op["receipt"]["result"]["value"]["providerReservationId"]

    assert [[event, input]] ==
             native(%{
               snapshot: searched,
               action: event,
               operation: op,
               refreshed: fresh,
               reconciled: true
             })
  end

  test "failure after entering cancellation retains its durable reservation for later reconciliation",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    reserved =
      Enum.reduce(~w(search reserve), original, fn event, current ->
        [[^event, input]] = native(%{snapshot: current, action: event})
        assert action(view, c.path, original, event, input)["snapshot"]["status"] == "completed"
        read(view, c.path, original)["snapshot"]
      end)

    [[event, input]] = native(%{snapshot: reserved, action: "cancel"})
    Application.put_env(:cadence, :ground_network_credentials, %{})
    op = action(view, c.path, original, event, input)["snapshot"]
    assert op["status"] == "unconfirmed"

    assert op["receipt"]["result"]["value"]["providerReservationId"] ==
             input["payload"]["reservation_evidence"]["reservation_id"]

    assert op["receipt"]["result"]["value"]["lifecycleState"] == "canceling"
    fresh = read(view, c.path, original)["snapshot"]

    assert [[event, input]] ==
             native(%{snapshot: reserved, action: event, operation: op, refreshed: fresh})

    refute_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
  end

  test "displayed routes and captured opportunities reject substitution before provider traffic",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    [[event, input]] = native(%{snapshot: original, action: "search"})
    bad = put_in(input, ["payload", "route_evidence", "provider_version"], 999)
    assert action(view, c.path, original, event, bad)["snapshot"]["status"] == "rejected"

    assert action(view, c.path, original, "reserve", %{
             sequence: 2,
             payload: %{token: String.duplicate("x", 500)}
           })["snapshot"]["status"] == "rejected"

    refute_receive {:provider, _, _}
    fresh = read(view, c.path, original)["snapshot"]
    assert fresh["data"]["model"]["initial_window"] == original["data"]["model"]["initial_window"]
  end

  def run(request), do: :persistent_term.get({__MODULE__, :handler}).(request)

  defp provider_response(request, data), do: {request, %Req.Response{status: 200, body: data}}
  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, p) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, p, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/CONTACT_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
  end

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
end
