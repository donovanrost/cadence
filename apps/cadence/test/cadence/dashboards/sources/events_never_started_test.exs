defmodule Cadence.Dashboards.Sources.EventsNeverStartedTest do
  @moduledoc """
  The contact-intervals frame's never-started fields (dashboards, ux 11-14): a realized contact
  closed without starting reads `started: false` with the sweep's `close_reason`, drawn at the
  scheduled window it belonged to; a started one reads true; open and scheduled rows read nil.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Contacts.{RealizedContact, ScheduledContact}
  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding, SourceResult}
  alias Cadence.Dashboards.Sources.Events
  alias Cadence.DataSources.{DataBinding, DataSource}

  @aos ~U[2026-06-17 12:01:00Z]
  @los ~U[2026-06-17 12:09:00Z]
  @swept_at "2026-06-17T12:14:00Z"

  test "a contact closed without starting is drawn at its scheduled window, with the reason" do
    contact =
      realized("real-a", "sched-a", :stopped, %{
        "not_started" => %{"at" => @swept_at, "reason" => "window_ended"}
      })

    assert %{
             "starts_at" => @aos,
             "ends_at" => @los,
             "started" => false,
             "close_reason" => "window_ended",
             "scheduled_starts_at" => @aos,
             "scheduled_ends_at" => @los
           } = row(contact, "real-a")
  end

  test "a started contact keeps its realized span and reads started true" do
    contact =
      realized("real-a", "sched-a", :completed, %{
        "started_at" => DateTime.to_iso8601(DateTime.add(@aos, 5)),
        "completed_at" => DateTime.to_iso8601(@los)
      })

    assert %{
             "starts_at" => @aos,
             "ends_at" => @los,
             "started" => true,
             "close_reason" => nil,
             "scheduled_starts_at" => nil,
             "scheduled_ends_at" => nil
           } = row(contact, "real-a", &no_fetch/3)
  end

  test "an open contact that hasn't started yet, and a scheduled row, read started nil" do
    contact = realized("real-a", "sched-a", :defined, %{})

    assert %{"started" => nil, "close_reason" => nil} = row(contact, "real-a", &no_fetch/3)
    assert %{"started" => nil, "close_reason" => nil} = row(contact, "sched-a", &no_fetch/3)
  end

  test "a hand start that never started keeps its realized span, to the sweep" do
    contact =
      realized("real-h", nil, :stopped, %{
        "not_started" => %{"at" => @swept_at, "reason" => "hand_start_expired"}
      })

    {:ok, swept, 0} = DateTime.from_iso8601(@swept_at)

    assert %{
             "starts_at" => @aos,
             "ends_at" => ^swept,
             "started" => false,
             "close_reason" => "hand_start_expired",
             "scheduled_starts_at" => nil
           } = row(contact, "real-h", &no_fetch/3)
  end

  test "a never-started contact whose scheduled contact is gone keeps its realized span" do
    contact =
      realized("real-a", "sched-a", :stopped, %{
        "not_started" => %{"at" => @swept_at, "reason" => "window_ended"}
      })

    missing = fn _org, _mission, _id -> {:error, :not_found} end

    assert %{"starts_at" => @aos, "started" => false, "scheduled_starts_at" => nil} =
             row(contact, "real-a", missing)
  end

  defp no_fetch(_org, _mission, id), do: flunk("fetched scheduled contact #{id}")

  defp realized(id, scheduled_id, state, metadata) do
    RealizedContact.new(%{
      realized_contact_id: id,
      scheduled_contact_id: scheduled_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      source_endpoint_refs: ["endpoint-a"],
      realized_at: @aos,
      lifecycle_state: state,
      metadata: metadata
    })
  end

  defp scheduled(org, mission) do
    ScheduledContact.new(%{
      scheduled_contact_id: "sched-a",
      organization_id: org,
      mission_id: mission,
      source_endpoint_refs: ["endpoint-a"],
      starts_at: @aos,
      ends_at: @los
    })
  end

  # One row of the contacts frame, by contact_id, as %{field_name => value}.
  defp row(contact, contact_id, fetch \\ &fetch_scheduled/3) do
    %SourceResult{frames: [frame]} =
      Events.resolve(
        source_request(),
        scheduled_contacts_fun: fn org, mission, _opts -> [scheduled(org, mission)] end,
        realized_contacts_fun: fn _org, _mission, _opts -> [contact] end,
        scheduled_contact_fun: fetch,
        source_endpoints_fun: fn _org, _mission ->
          [%{source_endpoint_id: "endpoint-a", spacecraft_id: "sc-1"}]
        end,
        source_binding: source_binding()
      )

    index =
      Enum.find(frame.fields, &(&1.name == "contact_id")).values
      |> Enum.find_index(&(&1 == contact_id))

    Map.new(frame.fields, &{&1.name, Enum.at(&1.values, index)})
  end

  defp fetch_scheduled("org-1", "mission-1", "sched-a"),
    do: {:ok, scheduled("org-1", "mission-1")}

  defp source_request do
    %PlannedSourceRequest{
      request_id: "events-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :events,
      observables: [],
      scope_context: %{
        organization_id: "org-1",
        mission_id: "mission-1",
        primary: %{kind: "mission", mode: "one", ids: ["mission-1"]}
      },
      time_context: %{
        axis: :receipt_time,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:20:00Z]
      },
      data_context: %{realm: :flight},
      sampling: %{mode: :event_history, products: [:contact_intervals], limit: 25},
      overlays: []
    }
  end

  defp source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "default_flight_events",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        logical_source: :events,
        data_source_id: "managed_events_projection",
        dataset: "mission_events"
      },
      data_source: %DataSource{
        data_source_id: "managed_events_projection",
        owner: :cadence,
        kind: :projection,
        isolation_level: :shared,
        adapter: Events,
        capabilities: %{contact_intervals?: true}
      },
      realm: :flight,
      dataset: "mission_events"
    }
  end
end
