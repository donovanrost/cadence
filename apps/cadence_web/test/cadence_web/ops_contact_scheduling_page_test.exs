Code.require_file(
  Path.expand("../../browser_test/support/dashboard_rendered_viewport_runner.exs", __DIR__)
)

Code.require_file(
  Path.expand("../../browser_test/support/federation_release_fixture.exs", __DIR__)
)

defmodule CadenceWeb.OpsContactSchedulingPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.{Accounts, Jobs, Repo}
  alias Cadence.Accounts.UserRow
  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Contacts.{ProviderReservations, ScheduleOperation, ScheduleOperations}
  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.GroundNetworks.ProviderContact
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Jobs.Supervisor, as: JobsSupervisor
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.ApplicationHostBridge
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: BrowserRunner
  alias CadenceWeb.Assets.FederationReleaseFixture
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

  test "both frontend inputs and the native transport use durable operations independent of the socket",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    [["search", search_input]] = native(%{snapshot: original, action: "search"})
    assert search_input["contract_version"] == 2
    found = action(view, c.path, original, "search", search_input)["snapshot"]
    assert [opportunity] = found["opportunities"]
    [["reserve", input]] = native(%{snapshot: original, action: "reserve", search: found})
    assert input["payload"] == %{"token" => opportunity["token"]}

    accepted = action(view, c.path, original, "reserve", input)["snapshot"]
    assert accepted["status"] == "accepted"
    assert accepted["operation_id"] == input["operation_id"]
    refute_receive {:provider, :post, "/provider/v1/contacts"}
    GenServer.stop(view.pid)
    run_operation(accepted["operation_id"])

    {:ok, returned, _} = live(c.conn, c.path)
    restored = page(returned)
    assert [completed] = restored["data"]["model"]["workflow"]["operations"]["entries"]
    assert completed["status"] == "completed"
    assert completed["result"]["lifecycleState"] == "confirmed"
    assert completed["operation_id"] == accepted["operation_id"]
    assert action(returned, c.path, restored, "reserve", input)["snapshot"] == completed
    assert [] == native(%{snapshot: restored})
    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  test "a lost acceptance is observed by operation ID without retrying provider traffic", c do
    {view, initial, input, accepted} = accept_reservation(c)

    observed =
      action(view, c.path, initial, "reserve", %{
        "contract_version" => 2,
        "operation_id" => input["operation_id"],
        "observe" => true
      })["snapshot"]["operation"]

    assert observed == accepted
    refute_receive {:provider, :post, "/provider/v1/contacts"}
    run_operation(input["operation_id"])

    op =
      action(view, c.path, initial, "reserve", %{
        "contract_version" => 2,
        "operation_id" => input["operation_id"],
        "observe" => true
      })["snapshot"]["operation"]

    assert op["status"] == "completed"
    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  test "input collisions and concurrent intents for the same reservation never enqueue a second effect",
       c do
    {view, initial, input, accepted} = accept_reservation(c)
    assert action(view, c.path, initial, "reserve", input)["snapshot"] == accepted
    changed = put_in(input, ["payload", "token"], "different")

    assert action(view, c.path, initial, "reserve", changed)["snapshot"]["status"] ==
             "not_accepted"

    other = %{input | "operation_id" => Ecto.UUID.generate()}
    assert action(view, c.path, initial, "reserve", other)["snapshot"]["status"] == "not_accepted"
    assert [_] = Jobs.list_jobs(:contact_schedule_operation, c.mission_id)
  end

  test "an unconfirmed provider outcome recovers after remount and job replay only observes", c do
    Agent.update(c.store, &Map.put(&1, :fail_booking, true))
    {view, _, input, _} = accept_reservation(c)
    run_operation(input["operation_id"])
    GenServer.stop(view.pid)
    {:ok, returned, _} = live(c.conn, c.path)
    [op] = page(returned)["data"]["model"]["workflow"]["operations"]["entries"]
    assert op["status"] == "unconfirmed"

    assert {:ok, row} =
             ProviderReservations.fetch(c.organization_id, c.mission_id, op["reservation_id"])

    external = contact(Agent.get(c.store, & &1.opportunity), row.idempotency_key, "confirmed", 2)
    assert {:ok, observed} = ProviderContact.from_external(external)

    assert {:ok, _} =
             ProviderReservations.apply_provider_status(
               c.organization_id,
               c.mission_id,
               row.provider_reservation_id,
               ProviderContact.to_reservation_result(observed)
             )

    assert {:ok, replayed} =
             ScheduleOperations.execute_enqueued_run(input["operation_id"])

    assert replayed.status == "completed"
    fresh = read(returned, c.path, page(returned))["snapshot"]
    assert [completed] = fresh["data"]["model"]["workflow"]["operations"]["entries"]
    assert completed["status"] == "completed"
    assert completed["revision"] > op["revision"]
    assert completed["reservation_id"] == row.provider_reservation_id
    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  test "worker reauthorizes the actor before provider I/O", c do
    {view, _, input, _} = accept_reservation(c)
    GenServer.stop(view.pid)

    c.user.user_id
    |> then(&Repo.get!(UserRow, &1))
    |> Ecto.Changeset.change(lifecycle_state: "disabled")
    |> Repo.update!()

    run_operation(input["operation_id"])

    row =
      Repo.get!(ScheduleOperation, input["operation_id"])

    assert row.status == "rejected"
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  test "operation recovery is scoped to its actor and mission", c do
    {_view, _, input, _} = accept_reservation(c)
    other = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(other, c.scope.organization, role: :organization_admin)
    {:ok, other_view, _} = live(TestFixtures.member_conn(other), c.path)
    other_page = page(other_view)
    assert other_page["data"]["model"]["workflow"]["operations"]["entries"] == []

    assert action(other_view, c.path, other_page, "reserve", %{
             "contract_version" => 2,
             "operation_id" => input["operation_id"],
             "observe" => true
           })["snapshot"] == %{"operation" => nil}

    assert action(other_view, c.path, other_page, "reserve", input)["snapshot"]["status"] ==
             "not_accepted"
  end

  test "cancellation keeps reviewed evidence and persists a definitive stale-review rejection",
       c do
    {view, initial, input, _} = accept_reservation(c)
    run_operation(input["operation_id"])
    fresh = read(view, c.path, initial)["snapshot"]
    [["cancel", cancel_input]] = native(%{snapshot: fresh, action: "cancel"})
    accepted = action(view, c.path, initial, "cancel", cancel_input)["snapshot"]
    assert accepted["status"] == "accepted"
    run_operation(accepted["operation_id"])
    canceled = read(view, c.path, initial)["snapshot"]
    [op | _] = canceled["data"]["model"]["workflow"]["operations"]["entries"]
    assert op["status"] == "completed"
    assert op["result"]["lifecycleState"] == "canceled"
    stale = %{cancel_input | "operation_id" => Ecto.UUID.generate()}
    accepted_stale = action(view, c.path, initial, "cancel", stale)["snapshot"]
    run_operation(accepted_stale["operation_id"])

    [stale_op | _] =
      read(view, c.path, initial)["snapshot"]["data"]["model"]["workflow"]["operations"][
        "entries"
      ]

    assert stale_op["status"] == "rejected"
    assert_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
    refute_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
  end

  test "the federated host bridge replays and observes the same durable operation as LiveVue",
       c do
    {_view, _initial, input, accepted} = accept_reservation(c)
    {:ok, membership} = Accounts.fetch_user_membership(c.user.user_id, c.organization_id)

    scope =
      Scope.new(%{
        user: c.user,
        organization_id: c.organization_id,
        organization: c.scope.organization,
        organization_membership: membership
      })

    route = %{
      host_context: HostContext.mission(c.mission_id),
      mission: c.mission,
      spacecraft: nil
    }

    params = %{
      "applicationKey" => "ops_console",
      "applicationVersion" => 1,
      "surfaceId" => "contact_schedule",
      "surfaceVersion" => 1,
      "actionId" => "reserve",
      "input" => input
    }

    assert {:ok, receipt} =
             ApplicationHostBridge.action(scope, route, params, "federated-acceptance",
               now: "2026-09-03T12:00:00Z"
             )

    assert receipt["result"]["operation_id"] == accepted["operation_id"]
    run_operation(input["operation_id"])

    observe =
      Map.put(params, "input", %{
        "contract_version" => 2,
        "operation_id" => input["operation_id"],
        "observe" => true
      })

    assert {:ok, receipt} =
             ApplicationHostBridge.action(
               scope,
               route,
               observe,
               "federated-observation",
               now: "2026-09-03T12:00:00Z"
             )

    assert receipt["result"]["operation"]["status"] == "completed"
    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
  end

  @tag :browser_smoke
  @tag timeout: 300_000
  test "production native, client-routed and federated scheduling share durable operations", c do
    output =
      Path.join(
        System.tmp_dir!(),
        "cadence-contact-schedule-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(output)
    port = BrowserRunner.start_browser_endpoint_on_ephemeral_port!(c.sandbox_owner)
    prepare_browser_release(c.sandbox_owner)
    start_supervised!({JobsSupervisor, safety_poll_interval_ms: 100, max_concurrency: 2})

    {log, status} =
      BrowserRunner.run_dashboard_viewport_smoke(
        [
          Path.expand("../../../../frontend/tools/phoenix/contact_schedule_browser.mjs", __DIR__),
          "http://127.0.0.1:#{port}",
          c.mission_id,
          c.spacecraft.spacecraft_id,
          c.user.email,
          output
        ],
        stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
        timeout: 240_000
      )

    assert status == 0, log <> "\nArtifacts: " <> output
    assert log =~ "CONTACT_SCHEDULE_BROWSER_OK"
    assert_receive {:provider, :post, "/provider/v1/contacts"}
    refute_receive {:provider, :post, "/provider/v1/contacts"}
    assert_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
    refute_receive {:provider, :post, "/provider/v1/contacts/provider-contact-one/cancel"}
  end

  defp prepare_browser_release(owner) do
    previous = Application.get_env(:cadence_web, :frontend_release_publication)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      FederationReleaseFixture.publication_config()
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence_web, :frontend_release_publication, previous),
        else: Application.delete_env(:cadence_web, :frontend_release_publication)
    end)

    release =
      FederationReleaseFixture.prepare_and_activate!(Path.expand("../..", __DIR__),
        sandbox_owner: owner,
        ops_console_surface: "contact_schedule"
      )

    on_exit(fn -> FederationReleaseFixture.cleanup!(release) end)
  end

  defp accept_reservation(c) do
    {:ok, view, _} = live(c.conn, c.path)
    initial = page(view)
    model = initial["data"]["model"]
    [route | _] = model["routes"]["entries"]

    search = %{
      "contract_version" => 2,
      "payload" => %{
        "contact_search" =>
          Map.merge(model["initial_window"], %{
            "spacecraft_id" => route["spacecraft_id"],
            "route_key" => route["key"]
          }),
        "route_evidence" => route["evidence"]
      }
    }

    found = action(view, c.path, initial, "search", search)["snapshot"]
    [opportunity] = found["opportunities"]

    input = %{
      "contract_version" => 2,
      "operation_id" => Ecto.UUID.generate(),
      "payload" => %{"token" => opportunity["token"]}
    }

    accepted = action(view, c.path, initial, "reserve", input)["snapshot"]
    assert accepted["status"] == "accepted", inspect(accepted)
    {view, initial, input, accepted}
  end

  defp run_operation(id) do
    jobs = Jobs.claim_jobs(100)
    job = Enum.find(jobs, &(&1.run_id == id))
    assert job
    assert {:ok, %{status: :completed}} = JobRunner.run_job(job.job_id)
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
