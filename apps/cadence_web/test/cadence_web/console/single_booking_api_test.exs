defmodule CadenceWeb.Console.SingleBookingAPITest do
  @moduledoc "§11 L15: the console's Book a pass (search, book, the pass row, the booker's release)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.TestFixtures

  setup do
    c = Fixtures.setup_schedule()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, c.scope.organization, role: :member)

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

    Map.merge(c, %{user: user, base: "/api/v1/missions/#{c.mission_id}"})
  end

  defp post_json(c, path, body),
    do: c.user |> TestFixtures.member_conn() |> post(c.base <> path, body)

  defp get_json(c, path), do: c.user |> TestFixtures.member_conn() |> get(c.base <> path)

  test "search, book with a note; the pass names its booker, who may release it", c do
    from = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.truncate(:second)

    search = %{
      "spacecraft_id" => c.spacecraft.spacecraft_id,
      "from" => DateTime.to_iso8601(from),
      "to" => DateTime.to_iso8601(DateTime.add(from, 86_400)),
      "direction" => "downlink"
    }

    found = json_response(post_json(c, "/single-bookings/search", search), 200)["data"]

    assert %{
             "offers" => [
               %{
                 "token" => token,
                 "station" => %{"ref" => _},
                 "overlaps" => nil,
                 # #892: no prediction has run for this mission, so prediction can't say.
                 "max_elevation_deg" => nil,
                 "elevation_source" => nil,
                 "predicted_pass_id" => nil,
                 "tca" => nil,
                 "no_predicted_pass" => nil
               }
             ],
             "not_ready" => _
           } =
             found

    booked =
      json_response(
        post_json(c, "/single-bookings", %{"token" => token, "note" => "Eclipse test"}),
        200
      )["data"]

    assert %{"outcome" => outcome, "reservation_id" => id} = booked
    assert outcome in ["requested", "confirmed"]

    # Until the provider job has written the reservation, there's no pass row yet: the bar
    # appears on the next contacts invalidation.
    if outcome == "requested", do: assert(booked["pass"] == nil)

    run_jobs()

    passes =
      json_response(get_json(c, "/passes?from=#{DateTime.to_iso8601(from)}"), 200)["data"][
        "passes"
      ]

    row = Enum.find(passes, &(&1["id"] == id))

    assert %{
             "off_plan" => %{
               "booked_by" => %{"name" => "Mira K."},
               "note" => "Eclipse test",
               "booked_at" => _
             },
             "releasable" => true
           } = row

    # The Timeline says who booked it outside a plan, with the note as the detail (L15).
    window =
      URI.encode_query(%{
        "from" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -600)),
        "to" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 600))
      })

    events = json_response(get_json(c, "/events?" <> window), 200)["data"]["events"]

    assert %{"kind" => "contact", "detail" => detail, "text" => text} =
             Enum.find(events, &(&1["raw_kind"] == "contact_booked_off_plan"))

    assert detail == "“Eclipse test” Doesn't count toward contact rules."

    # U69 A8b: the merged off-plan row reads back by its id (a permalink).
    off_plan = Enum.find(events, &(&1["raw_kind"] == "contact_booked_off_plan"))

    assert %{"id" => id_again, "detail" => ^detail} =
             c
             |> get_json("/events/" <> URI.encode_www_form(off_plan["id"]))
             |> json_response(200)
             |> get_in(["data", "event"])

    assert id_again == off_plan["id"]
    assert text =~ ~r/ booked outside a plan by Mira K\.$/

    stale =
      post_json(c, "/passes/#{id}/release", %{
        "expected_provider_revision" => row["provider_revision"] + 7
      })

    assert %{"code" => "pass_changed", "details" => %{"pass" => %{"id" => ^id}}} =
             json_response(stale, 409)["error"]
  end

  test "a bad window is 422 on its field; a token that isn't ours can't be booked", c do
    past = DateTime.utc_now() |> DateTime.add(-86_400) |> DateTime.to_iso8601()

    bad = %{
      "spacecraft_id" => c.spacecraft.spacecraft_id,
      "from" => past,
      "to" => past,
      "direction" => "downlink"
    }

    assert %{"code" => "invalid_params"} =
             json_response(post_json(c, "/single-bookings/search", bad), 422)["error"]

    assert %{"code" => code} =
             json_response(post_json(c, "/single-bookings", %{"token" => "forged"}), 422)["error"]

    assert code in ["token_invalid", "invalid_params"]
  end

  test "A16b: the route picker reads the ready routes and limits; search takes route_keys and the reach",
       c do
    routes =
      c
      |> get_json("/single-bookings/routes?spacecraft_id=#{c.spacecraft.spacecraft_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "spacecraft" => %{"id" => _},
             "routes" => [route | _],
             "limits" => %{
               "max_window_s" => 604_800,
               "max_reach_s" => reach_s,
               "reach_until" => until
             }
           } = routes

    assert %{"key" => key, "name" => _, "provider" => %{"id" => _}, "transport" => %{"id" => _}} =
             route

    assert Map.has_key?(route, "station") and Map.has_key?(route, "uplink")
    assert reach_s == 14 * 86_400 and is_binary(until)

    from = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.truncate(:second)

    search = fn extra ->
      post_json(
        c,
        "/single-bookings/search",
        Map.merge(
          %{
            "spacecraft_id" => c.spacecraft.spacecraft_id,
            "from" => DateTime.to_iso8601(from),
            "to" => DateTime.to_iso8601(DateTime.add(from, 86_400)),
            "direction" => "downlink"
          },
          extra
        )
      )
    end

    assert %{"offers" => [_ | _]} = json_response(search.(%{"route_keys" => [key]}), 200)["data"]

    assert %{"details" => %{"route_keys" => _}} =
             json_response(search.(%{"route_keys" => ["nope"]}), 422)["error"]

    far = DateTime.add(DateTime.utc_now(), 20 * 86_400) |> DateTime.truncate(:second)

    assert %{"details" => %{"to" => message}} =
             json_response(
               search.(%{
                 "from" => DateTime.to_iso8601(DateTime.add(far, -3_600)),
                 "to" => DateTime.to_iso8601(far)
               }),
               422
             )["error"]

    assert message =~ "Search up to"

    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             json_response(get_json(c, "/single-bookings/routes?spacecraft_id=nope"), 404)
  end

  defp run_jobs, do: for(job <- Jobs.claim_jobs(100), do: JobRunner.run_job(job.job_id))

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

      "/provider/v1/contacts/provider-contact-one" ->
        respond(request, %{"data" => Agent.get(store, & &1.contact)})
    end
  end

  defp respond(request, data), do: {request, %Req.Response{status: 200, body: data}}
  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)

  # The fake provider's confirmed contact for the searched opportunity (as single_bookings_test).
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
          "source_addresses" => ["127.0.0.1/32", "::1/128"],
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
