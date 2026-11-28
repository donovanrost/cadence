defmodule Cadence.Reads.PassListenerOverlapTest do
  @moduledoc """
  #361 (U58 (b)): the reads' listener_overlap for planned passes and Book a pass offers. A planned
  pass's or an offer's listeners come from its route's path template, resolved as a booking's
  would be. Each is checked against the mission's booked passes, a plan's own bookings left out.
  """
  use Cadence.DataCase, async: false

  alias Cadence.{CommandGroupFixtures, Contacts}

  alias Cadence.Contacts.{
    ContactRuntimeConfig,
    LinkAssignment,
    LinkAssignmentStore,
    ListenerOverlap,
    Path,
    PathTemplate,
    PathTemplateStore,
    ProfileStore,
    ProviderBinding,
    ProviderProfile,
    ScheduledContact,
    TransportProfile
  }

  alias Cadence.Reads.{Passes, PassListenerOverlap}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @port 45_105
  @t0 ~U[2026-11-21 00:00:00Z]

  setup do
    org = "org-overlap-#{System.unique_integer([:positive])}"
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission = "mission-overlap-" <> suffix
    persist_mission_scope(org, mission)

    craft =
      Spacecraft.new(%{
        spacecraft_id: "sc-" <> suffix,
        mission_id: mission,
        display_name: "EARENDIL-006"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org, craft)

    {:ok, endpoint} =
      Cadence.SourceEndpointFixtures.persist(
        org,
        SourceEndpoint.new(%{
          source_endpoint_id: "ep-" <> suffix,
          mission_id: mission,
          spacecraft_id: craft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    {:ok, profile} =
      Contacts.persist_provider_profile(
        org,
        ProviderProfile.new(%{
          provider_profile_id: "listen-" <> suffix,
          mission_id: mission,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
            "port" => @port,
            "ingress_protocol_family" => "tm",
            "frame_size" => 10
          }
        })
      )

    {:ok, template} =
      Contacts.persist_path_template(
        org,
        PathTemplate.new(%{
          path_template_id: "tpl-" <> suffix,
          mission_id: mission,
          path_id: "path-" <> suffix,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: endpoint.source_endpoint_id,
          provider_profile_refs: [
            %{"provider_profile_id" => profile.provider_profile_id, "version" => profile.version}
          ]
        })
      )

    %{
      org: org,
      mission: mission,
      craft: craft,
      endpoint: endpoint,
      profile: profile,
      template: template
    }
  end

  defp at(s), do: DateTime.add(@t0, s, :second)

  defp book!(c, name, from, to) do
    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "#{name}-#{System.unique_integer([:positive])}",
        mission_id: c.mission,
        source_endpoint_refs: [c.endpoint.source_endpoint_id],
        starts_at: at(from),
        ends_at: at(to),
        paths: [
          Path.new(%{
            path_id: "p-#{name}",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: c.endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: c.profile.provider_profile_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  expected_peer_addresses: ["127.0.0.1/32", "::1/128"],
                  port: @port,
                  ingress_protocol_family: :tm,
                  frame_size: 10
                }
              })
            ]
          })
        ]
      })

    {:ok, scheduled} = Contacts.persist_scheduled_contact(c.org, contact)
    scheduled
  end

  defp route(c),
    do: %{
      path_template_id: c.template.path_template_id,
      path_template_version: c.template.version
    }

  test "a route's path template resolves to its own listener", c do
    assert [%{port: @port, direction: :downlink}] =
             ListenerOverlap.template_listeners(
               c.org,
               c.mission,
               c.template.path_template_id,
               c.template.version
             )

    assert [] = ListenerOverlap.template_listeners(c.org, c.mission, nil, nil)
  end

  test "an offer starting inside a booked pass on the same listener is flagged, naming that pass",
       c do
    booked = book!(c, "006", 0, 600)

    offer = %{
      "id" => "offer-1",
      "starts_at" => DateTime.to_iso8601(at(574)),
      "ends_at" => DateTime.to_iso8601(at(1200))
    }

    clear = %{
      "id" => "offer-2",
      "starts_at" => DateTime.to_iso8601(at(700)),
      "ends_at" => DateTime.to_iso8601(at(1200))
    }

    result =
      PassListenerOverlap.for_offers(c.org, c.mission, [{route(c), offer}, {route(c), clear}])

    assert %{
             seconds: 26,
             loses: "this",
             direction: "downlink",
             count: 1,
             listener: %{port: @port}
           } = result["offer-1"]

    assert %{state: "booked", starts_at: starts, spacecraft: %{id: _}} = result["offer-1"].with
    assert starts == booked.starts_at
    assert result["offer-2"] == nil
  end

  # A real reservation needs a requirement and a plan behind it (foreign keys), so the rule that
  # leaves a plan's own bookings out is tested directly; for_plan/4 calls it.
  test "a plan's own bookings are recognised by their reservation's snapshot (domain, api-ops)" do
    reservations = [
      %{contact_opportunity_snapshot_id: "snap-own", scheduled_contact_id: "contact-own"},
      %{
        contact_opportunity_snapshot_id: "snap-other-plan",
        scheduled_contact_id: "contact-rival"
      },
      %{contact_opportunity_snapshot_id: nil, scheduled_contact_id: "contact-direct"},
      %{contact_opportunity_snapshot_id: "snap-own", scheduled_contact_id: nil}
    ]

    assert PassListenerOverlap.own_booking_ids(reservations, MapSet.new(["snap-own"])) ==
             MapSet.new(["contact-own"])
  end

  test "an offer without a readable time is left unflagged, not a crash (api-ops)", c do
    _booked = book!(c, "006", 0, 600)
    untimed = %{"id" => "offer-x", "starts_at" => "not a time", "ends_at" => nil}

    assert %{"offer-x" => nil} =
             PassListenerOverlap.for_offers(c.org, c.mission, [{route(c), untimed}])
  end

  test "a plan's pass is checked against the mission's booked passes", c do
    _other = book!(c, "006", 0, 600)

    snapshot = %{
      contact_opportunity_snapshot_id: "snap-1",
      starts_at: at(574),
      ends_at: at(1200),
      route_binding_document: %{
        "path_template_id" => c.template.path_template_id,
        "path_template_version" => c.template.version,
        "spacecraft_id" => c.craft.spacecraft_id
      },
      normalized_opportunity_document: %{}
    }

    assert %{"snap-1" => %{loses: "this", seconds: 26, with: %{state: "booked"}}} =
             PassListenerOverlap.for_plan(c.org, c.mission, [snapshot], %{})
  end

  # ca-security (#361): contention stays inside one mission because no other mission, in any
  # organization, can save a listen endpoint this mission holds. The read relies on this guard.
  test "another organization's mission can't listen on this mission's endpoint", _c do
    other_org = "org-other-#{System.unique_integer([:positive])}"
    other_mission = "mission-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(other_org, other_mission)

    assert {:error, {:listen_endpoint_claimed, %{port: @port}}} =
             Contacts.persist_provider_profile(
               other_org,
               ProviderProfile.new(%{
                 provider_profile_id: "intruder",
                 mission_id: other_mission,
                 adapter_key: :tcp_socket,
                 configuration: %{
                   "mode" => "listen",
                   "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
                   "port" => @port,
                   "ingress_protocol_family" => "tm",
                   "frame_size" => 10
                 }
               })
             )
  end

  # api-ops (#640): the read's queries don't grow with the passes it compares. Passes on one route
  # resolve once, the pairing is a sweep, and the named pass's facts come from the contacts
  # already loaded.
  test "the booked-pass read runs the same queries for 2 passes as for 8 on one route", c do
    small = for i <- 1..2, do: book!(c, "same", i * 100, i * 100 + 600)
    small_rows = Enum.map(small, &%{starts_at: &1.starts_at, ends_at: &1.ends_at})

    small_count =
      count_queries(fn -> PassListenerOverlap.for_rows(c.org, c.mission, small_rows) end)

    for i <- 3..8, do: book!(c, "same", i * 100, i * 100 + 600)
    rows = [%{starts_at: at(100), ends_at: at(1400)}]
    large_count = count_queries(fn -> PassListenerOverlap.for_rows(c.org, c.mission, rows) end)

    assert large_count == small_count
    IO.puts("#361 query count: #{small_count} for 2 passes, #{large_count} for 8")
  end

  test "listeners match the runtime for inline paths, pinned templates and link assignments", c do
    inline = book!(c, "inline", 0, 600)
    port = @port + 1

    assert {:ok, profile} =
             ProfileStore.version_provider_profile(
               c.org,
               c.mission,
               c.profile.provider_profile_id,
               %{
                 configuration: Map.put(c.profile.configuration, "port", port),
                 metadata: %{"materialized_from_transport_id" => "transport-example"}
               }
             )

    assert {:ok, template} =
             PathTemplateStore.version(c.org, c.mission, c.template.path_template_id, %{
               provider_profile_refs: [profile_ref(profile)]
             })

    assignment = link_assignment!(c, c.template, [profile_ref(profile)])

    pinned = scheduled(c, "pinned", %{path_template_refs: [template_ref(c.template)]})
    latest = scheduled(c, "latest", %{path_template_ids: [template.path_template_id]})

    assigned =
      scheduled(c, "assigned", %{
        link_assignment_refs: [%{"link_assignment_id" => assignment.link_assignment_id}]
      })

    mixed = %{
      assigned
      | scheduled_contact_id: "mixed",
        path_template_refs: pinned.path_template_refs,
        paths: inline.paths
    }

    missing = scheduled(c, "missing", %{path_template_ids: ["missing-template"]})
    contacts = [inline, pinned, latest, assigned, mixed, missing]

    assert_listener_parity(contacts, %{
      inline.scheduled_contact_id => [listener(@port)],
      "pinned" => [listener(@port)],
      "latest" => [listener(port)],
      "assigned" => [listener(port)],
      "mixed" => [listener(port), listener(@port)],
      "missing" => []
    })

    assert {:ok, _} =
             ProfileStore.delete_provider_profile(
               c.org,
               c.mission,
               profile.provider_profile_id,
               %{}
             )

    assert {:error, {:contact_provider_profile_archived, %{transport_id: "transport-example"}}} =
             ContactRuntimeConfig.resolve_paths(assigned)

    assert_listener_parity(contacts, %{
      inline.scheduled_contact_id => [listener(@port)],
      "pinned" => [],
      "latest" => [],
      "assigned" => [],
      "mixed" => [],
      "missing" => []
    })
  end

  test "scheduled listeners and passes use fixed query counts at 5 and 50 distinct routes", c do
    assert {:ok, transport} =
             ProfileStore.persist_transport_profile(
               c.org,
               TransportProfile.new(%{
                 transport_profile_id: "shared-transport",
                 mission_id: c.mission,
                 family_key: :uplink_gateway,
                 target_scope: :path
               })
             )

    booking =
      CommandGroupFixtures.commandable_pass!(c.org, c.mission, c.craft.spacecraft_id, at(5))

    c = Map.merge(c, %{booking: booking, transport: transport})

    small = Enum.map(1..5, &book_distinct_route!(c, &1))
    small_resolve = count_queries(fn -> ListenerOverlap.scheduled_listeners_by_id(small) end)
    small_read = count_queries(fn -> assert_booking_overlap(c) end)

    large = small ++ Enum.map(6..50, &book_distinct_route!(c, &1))
    large_resolve = count_queries(fn -> ListenerOverlap.scheduled_listeners_by_id(large) end)
    large_read = count_queries(fn -> assert_booking_overlap(c) end)

    assert small_resolve == 4
    assert small_resolve == large_resolve
    assert small_read == large_read
  end

  defp scheduled(c, id, attrs) do
    ScheduledContact.new(
      Map.merge(
        %{
          scheduled_contact_id: id,
          organization_id: c.org,
          mission_id: c.mission,
          source_endpoint_refs: [c.endpoint.source_endpoint_id],
          starts_at: at(0),
          ends_at: at(600)
        },
        attrs
      )
    )
  end

  defp template_ref(template),
    do: %{"path_template_id" => template.path_template_id, "version" => template.version}

  defp profile_ref(profile),
    do: %{"provider_profile_id" => profile.provider_profile_id, "version" => profile.version}

  defp listener(port), do: %{host: "127.0.0.1", port: port, direction: :downlink}

  defp assert_listener_parity(contacts, expected) do
    runtime =
      Map.new(contacts, fn contact ->
        listeners =
          case ContactRuntimeConfig.resolve_paths(contact) do
            {:ok, paths} -> ListenerOverlap.listeners(paths)
            {:error, _reason} -> []
          end

        {contact.scheduled_contact_id, listeners}
      end)

    assert runtime == expected
    assert ListenerOverlap.scheduled_listeners_by_id(contacts) == runtime
  end

  defp link_assignment!(c, template, provider_refs \\ []) do
    assert {:ok, assignment} =
             LinkAssignmentStore.persist(
               c.org,
               LinkAssignment.new(%{
                 mission_id: c.mission,
                 spacecraft_id: c.craft.spacecraft_id,
                 source_endpoint_ref: c.endpoint.source_endpoint_id,
                 path_template_id: template.path_template_id,
                 path_template_version: template.version,
                 direction: template.direction,
                 selection_role: template.selection_role,
                 provider_profile_refs: provider_refs
               })
             )

    assignment
  end

  defp book_distinct_route!(c, i) do
    {craft, endpoint, id} =
      if i == 1 do
        {c.craft, c.endpoint, c.booking.scheduled_contact_id}
      else
        craft_and_endpoint!(c, i)
      end

    assert {:ok, template} =
             PathTemplateStore.persist(c.org, %{
               c.template
               | path_template_id: "template-" <> craft.spacecraft_id,
                 transport_profile_refs: [
                   %{
                     "transport_profile_id" => c.transport.transport_profile_id,
                     "version" => c.transport.version
                   }
                 ]
             })

    c = %{c | craft: craft, endpoint: endpoint}
    assignment = link_assignment!(c, template)

    contact =
      scheduled(c, id, %{
        starts_at: at(i * 5),
        ends_at: at(i * 5 + 600),
        link_assignment_refs: [%{"link_assignment_id" => assignment.link_assignment_id}]
      })

    assert {:ok, contact} = Contacts.persist_scheduled_contact(c.org, contact)
    contact
  end

  defp craft_and_endpoint!(c, i) do
    assert {:ok, craft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               c.org,
               Spacecraft.new(%{mission_id: c.mission, display_name: "Craft #{i}"})
             )

    assert {:ok, endpoint} =
             Cadence.SourceEndpointFixtures.persist(
               c.org,
               SourceEndpoint.new(%{
                 mission_id: c.mission,
                 spacecraft_id: craft.spacecraft_id,
                 source_ref: "provider/tcp/#{i}"
               })
             )

    {craft, endpoint, "pass-#{i}"}
  end

  defp assert_booking_overlap(c) do
    assert {:ok, %{passes: [%{listener_overlap: %{loses: "other"}}]}} =
             Passes.page(c.org, c.mission, at(0), at(1200), %{})
  end

  defp count_queries(fun) do
    me = self()
    handler = "count-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _ -> if self() == me, do: send(me, :query) end,
      nil
    )

    try do
      fun.()
      drain(0)
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end
end
