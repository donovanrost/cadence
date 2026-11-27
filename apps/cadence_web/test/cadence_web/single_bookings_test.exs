defmodule CadenceWeb.SingleBookingsTest do
  @moduledoc "Book a pass outside a plan, through Contacts.SingleBookings (L15, DECISIONS #78)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.OpportunityCapability
  alias Cadence.Contacts.{ProviderReservations, SingleBookings}
  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.TestFixtures

  setup do
    c = Fixtures.setup_schedule()
    user = TestFixtures.persist_user!()

    membership =
      TestFixtures.grant_membership!(user, c.scope.organization, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: c.scope.organization_id,
        organization_membership: membership
      })

    defaults = Req.default_options()
    local = Application.get_env(:cadence, :provider_local_credentials)
    credentials = Application.get_env(:cadence, :ground_network_credentials)
    Application.put_env(:cadence, :provider_local_credentials, enabled: true)

    Application.put_env(:cadence, :ground_network_credentials, %{
      "simulator" => "test-only-secret"
    })

    {:ok, store} = Agent.start_link(fn -> %{contact: nil} end)
    :persistent_term.put({__MODULE__, :handler}, &handle(&1, c, store))
    Req.default_options(adapter: __MODULE__, retry: false)

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :handler})
      Req.default_options(defaults)
      restore(:provider_local_credentials, local)
      restore(:ground_network_credentials, credentials)
    end)

    Map.merge(c, %{user: user, booker: scope})
  end

  test "search, book with a note, and the booker cancels at the revision they saw", c do
    from = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.truncate(:second)

    assert {:ok, found} =
             SingleBookings.search(c.booker, c.mission_id, %{
               "spacecraft_id" => c.spacecraft.spacecraft_id,
               "from" => DateTime.to_iso8601(from),
               "to" => DateTime.to_iso8601(DateTime.add(from, 86_400)),
               "direction" => "downlink"
             })

    assert [%{token: token, overlaps: nil, provider: %{id: _}} = offer] = found.offers
    assert offer.uplink_capable in [true, false]
    assert found.hidden == %{no_uplink_route: 0}

    # The provider is answered by the job, not the request: the first answer may come later.
    assert {:ok, %{outcome: outcome, reservation_id: id}} =
             SingleBookings.reserve(c.booker, c.mission_id, %{
               "token" => token,
               "note" => "Extra pass for the eclipse test"
             })

    assert outcome in ["requested", "confirmed"]
    run_jobs()

    {:ok, booked} = ProviderReservations.fetch(c.scope.organization_id, c.mission_id, id)
    assert booked.lifecycle_state == :confirmed
    assert booked.contact_plan_id == nil

    assert %{
             "booked_by" => %{"kind" => "user", "id" => booker_id},
             "booked_at" => _at,
             "note" => "Extra pass for the eclipse test"
           } = booked.metadata["off_plan"]

    assert booker_id == c.user.user_id

    # Only the booker may cancel without managing missions.
    assert SingleBookings.cancel_permission(c.scope.organization_id, c.mission_id, id, booker_id) ==
             :operate_mission

    assert SingleBookings.cancel_permission(c.scope.organization_id, c.mission_id, id, "someone") ==
             :manage_missions

    # Booked again with the same token: the same booking.
    assert {:ok, %{reservation_id: ^id}} =
             SingleBookings.reserve(c.booker, c.mission_id, %{"token" => token, "note" => nil})

    # A stale revision is refused with the current booking.
    assert {:error, {:booking_changed, %{provider_reservation_id: ^id}}} =
             SingleBookings.cancel(c.booker, c.mission_id, id, booked.provider_revision + 1)

    assert {:ok, %{outcome: canceled}} =
             SingleBookings.cancel(c.booker, c.mission_id, id, booked.provider_revision)

    assert canceled in ["requested", "canceled"]
    run_jobs()

    {:ok, after_cancel} = ProviderReservations.fetch(c.scope.organization_id, c.mission_id, id)
    assert after_cancel.lifecycle_state == :canceled
  end

  test "bad windows and tokens are closed-set errors", c do
    past = DateTime.utc_now() |> DateTime.add(-86_400) |> DateTime.to_iso8601()

    assert {:error, {:invalid, %{"to" => "The window is in the past"}}} =
             SingleBookings.search(c.booker, c.mission_id, %{
               "spacecraft_id" => c.spacecraft.spacecraft_id,
               "from" => past,
               "to" => past
             })

    assert {:error, :token_invalid} =
             SingleBookings.reserve(c.booker, c.mission_id, %{"token" => "not-a-token"})

    assert {:error, {:invalid, %{"note" => _}}} =
             SingleBookings.reserve(c.booker, c.mission_id, %{
               "token" => "x",
               "note" => String.duplicate("a", 501)
             })

    assert {:error, :not_found} = SingleBookings.cancel(c.booker, c.mission_id, "nope", 1)
  end

  test "an offer older than its capability's age says it expired", c do
    from = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.truncate(:second)

    {:ok, %{offers: [%{token: token}]}} =
      SingleBookings.search(c.booker, c.mission_id, %{
        "spacecraft_id" => c.spacecraft.spacecraft_id,
        "from" => DateTime.to_iso8601(from),
        "to" => DateTime.to_iso8601(DateTime.add(from, 86_400)),
        "direction" => "downlink"
      })

    # The same genuine offer, issued 1,000 s ago (the limit is 900).
    {:ok, payload} = OpportunityCapability.verify(token)

    stale =
      payload
      |> Map.delete("issued_at")
      |> OpportunityCapability.sign(issued_at: System.system_time(:second) - 1_000)

    assert {:error, :opportunity_expired} =
             SingleBookings.reserve(c.booker, c.mission_id, %{"token" => stale})
  end

  defp run_jobs do
    for job <- Jobs.claim_jobs(100), do: JobRunner.run_job(job.job_id)
  end

  def run(request), do: :persistent_term.get({__MODULE__, :handler}).(request)

  defp handle(request, c, store) do
    case request.url.path do
      "/provider/v1/capabilities" ->
        {:ok, caps} = FakeProviderClient.capabilities(nil, [])
        respond(request, %{"data" => caps.evidence})

      "/provider/v1/opportunities/search" ->
        attrs = request.body |> IO.iodata_to_binary() |> Jason.decode!()
        {:ok, start, _} = DateTime.from_iso8601(attrs["starts_at"])
        opportunity = Fixtures.opportunity(c.route, start)
        Agent.update(store, &Map.put(&1, :opportunity, opportunity))
        respond(request, %{"data" => [opportunity], "meta" => %{}})

      "/provider/v1/contacts" ->
        attrs = request.body |> IO.iodata_to_binary() |> Jason.decode!()
        contact = contact(Agent.get(store, & &1.opportunity), attrs["client_reference"])
        Agent.update(store, &Map.put(&1, :contact, contact))
        respond(request, %{"data" => contact})

      "/provider/v1/contacts/provider-contact-one/cancel" ->
        contact =
          Map.merge(Agent.get(store, & &1.contact), %{"status" => "canceled", "revision" => 2})

        respond(request, %{"data" => contact})

      "/provider/v1/contacts/provider-contact-one" ->
        respond(request, %{"data" => Agent.get(store, & &1.contact)})
    end
  end

  defp respond(request, data), do: {request, %Req.Response{status: 200, body: data}}
  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)

  defp contact(o, client),
    do:
      o
      |> Map.drop(["availability", "expires_at", "synthetic"])
      |> Map.merge(%{
        "id" => "provider-contact-one",
        "provider_contact_ref" => "provider-contact-one",
        "opportunity_ref" => o["id"],
        "delivery_profile_ref" => "delivery-cadence",
        "client_reference" => client,
        "status" => "confirmed",
        "revision" => 1,
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
