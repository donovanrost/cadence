defmodule Cadence.Reads.ActionQueue.AttentionItemsTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.ActionQueue
  alias Cadence.Reads.ActionQueue.{AttentionItems, Item}

  @now ~U[2026-11-09 18:00:00Z]

  defp at(seconds), do: DateTime.add(@now, seconds)

  defp names do
    member =
      Item.member(%{
        id: "sc-1",
        name: "EARENDIL-001",
        scid: 1,
        plane: 1,
        stale: false,
        last_received_at: at(-60),
        violating_points: 0
      })

    %{
      spacecraft: %{"sc-1" => member},
      station: &%{ref: &1, id: "gs-svb", code: "SVB-1", name: "Svalbard 1"},
      providers: %{"northlight" => %{id: "northlight", name: "Northlight"}}
    }
  end

  defp attention(id, starts_in_s, opts \\ []) do
    %{
      id: id,
      source: "pass_resolution",
      conflict: Keyword.get(opts, :conflict, "contradicts_attestation"),
      state: Keyword.get(opts, :state, "open"),
      acknowledged_by: nil,
      spacecraft_id: "sc-1",
      contact_id: "contact-#{id}",
      provider_contact_ref: "NL-1",
      ground_station_ref: "svb",
      provider_id: "northlight",
      starts_at: at(starts_in_s),
      ends_at: at(starts_in_s + 600),
      raised_at: at(-300),
      provider_message: nil,
      resolution: %{
        action: "booked",
        actor: %{"kind" => "user", "id" => "u1", "name" => "Mira K."}
      }
    }
  end

  defp build(items, resolved \\ []),
    do: AttentionItems.build(%{items: items, resolved: resolved}, names(), @now)

  test "a pass within 2 h, or under way, is P1; a later one is P2" do
    %{items: [soon, under_way, later]} =
      build([
        attention("a", 2 * 3600),
        attention("b", -120),
        attention("c", 2 * 3600 + 1)
      ])

    assert %{id: "attention:pass_resolution:a", priority: 1, state: :critical} = soon
    assert %{priority: 1} = under_way
    assert %{priority: 2, state: :caution} = later
  end

  test "rows name the spacecraft, station and provider, with the pass start as due_at" do
    %{items: [item]} = build([attention("a", 600)])

    assert %{
             kind: :attention,
             source: "pass_resolution",
             count: 1,
             due_at: due_at,
             since: since,
             spacecraft: [%{id: "sc-1", name: "EARENDIL-001", scid: 1, episode_id: nil}],
             attention: %{
               id: "a",
               conflict: "contradicts_attestation",
               contact_id: "contact-a",
               station: %{code: "SVB-1", name: "Svalbard 1"},
               provider: %{id: "northlight", name: "Northlight"}
             }
           } = item

    assert due_at == at(600)
    assert since == at(-300)
  end

  test "acknowledged attention sorts after open attention of the same priority" do
    %{items: items, resolved: resolved} =
      build([attention("acked", 3 * 3600, state: "acknowledged"), attention("open", 4 * 3600)])

    queue =
      ActionQueue.build(%{
        fleet: %{stale_after_s: 900, spacecraft: []},
        now: @now,
        failure_lookback_s: 86_400,
        limits_configured?: true,
        viewer_user_id: "viewer",
        attention: %{items: items, resolved: resolved}
      })

    assert Enum.map(queue.items, & &1.id) == [
             "attention:pass_resolution:open",
             "attention:pass_resolution:acked"
           ]

    assert queue.counts.p2 == 2
  end

  test "a pass_release item carries its cancel outcome as release; others have release nil" do
    release =
      "r"
      |> attention(600)
      |> Map.merge(%{
        source: "pass_release",
        conflict: "cancel_failed",
        outcome: "refused",
        provider_reason: "conflict"
      })

    %{items: [released, resolution]} = build([release, attention("a", 600)])

    assert %{
             id: "attention:pass_release:r",
             attention: %{release: %{outcome: "refused", reason: "conflict"}}
           } =
             released

    assert resolution.attention.release == nil
  end

  test "resolved entries match row ids and say who or what closed them" do
    resolved =
      [
        {"u", %{"kind" => "user", "id" => "u1", "name" => "Mira K."}, "booked"},
        {"p", %{"kind" => "provider", "id" => "northlight"}, "confirmed"},
        {"s", %{"kind" => "system"}, "cancel confirmed"}
      ]
      |> Enum.map(fn {id, by, action} ->
        %{id: id, source: "pass_resolution", resolved_by: by, action: action, resolved_at: @now}
      end)

    %{resolved: [user, provider, system]} = build([], resolved)

    assert %{id: "attention:pass_resolution:u", resolved_by: %{kind: "user", name: "Mira K."}} =
             user

    assert %{resolved_by: %{kind: "provider", name: "Northlight"}, action: "confirmed"} = provider
    assert %{resolved_by: %{kind: "system", name: nil}, action: "cancel confirmed"} = system
  end

  test "a stuck activation apply: P1 only while the runtime is down, with its members and facts" do
    stuck = fn runtime_not_applied ->
      %{
        id: "activation_request_1",
        source: "activation_apply",
        conflict: "apply_failed",
        state: "open",
        error_code: "activation_execution_interrupted",
        error: "Applying was cut off: Cadence lost its database connection partway.",
        retryable: true,
        activation_request_id: "activation_request_1",
        summary: "Decom composition for 2 spacecraft",
        kind: "telemetry_decom",
        app: %{key: "telemetry_decom", name: "Telemetry Decom"},
        spacecraft_ids: ["sc-1", "sc-gone"],
        spacecraft_id: nil,
        spacecraft_count: 2,
        runtime_not_applied: runtime_not_applied,
        approved_by: %{id: "u1", name: "Mira K."},
        approved_at: at(-600),
        since: at(-300),
        raised_at: at(-300)
      }
    end

    %{items: [down]} = build([stuck.(true)], [])
    %{items: [up]} = build([stuck.(false)], [])

    assert {down.priority, up.priority} == {1, 2}
    assert down.id == "attention:activation_apply:activation_request_1"
    # Members the fleet knows; one that left it is skipped here (names come from load/4).
    assert [%{id: "sc-1"}] = down.spacecraft

    assert %{
             retryable: true,
             error_code: "activation_execution_interrupted",
             approved_by: %{name: "Mira K."},
             runtime_not_applied: true,
             contact_id: nil,
             starts_at: nil
           } = down.attention
  end

  test "a provider change: approval P2 until its deadline, then P3; acknowledgement P3" do
    change = fn conflict, deadline ->
      %{
        id: "change-#{conflict}",
        source: "provider_change",
        conflict: conflict,
        state: "open",
        spacecraft_id: "sc-1",
        contact_id: nil,
        ground_station_ref: nil,
        provider_id: nil,
        starts_at: at(7200),
        raised_at: at(-60),
        deadline_at: deadline,
        provider_change: %{id: "change-#{conflict}"}
      }
    end

    %{items: items} =
      build(
        [
          change.("approval_required", at(600)),
          change.("approval_required", at(-600)),
          change.("acknowledgment_required", at(600))
        ],
        []
      )

    assert Enum.map(items, & &1.priority) == [2, 3, 3]
    assert hd(items).due_at == at(600)
  end

  test "U61: a plan_coverage resolution carries the words its line needs; others don't" do
    coverage = %{
      id: "plan_coverage:2026-11-16",
      source: "plan_coverage",
      resolved_by: %{"kind" => "system"},
      action: "day_ended",
      resolved_at: @now,
      day: ~D[2026-11-16],
      from_state: "interrupted",
      plan_revision: 41,
      booking: %{reserved: 12, total: 41}
    }

    other = %{
      id: "x",
      source: "contact_start",
      resolved_by: %{"kind" => "system"},
      action: "started",
      resolved_at: @now
    }

    %{resolved: [line, plain]} = build([], [coverage, other])

    assert %{
             action: "day_ended",
             day: ~D[2026-11-16],
             from_state: "interrupted",
             plan_revision: 41,
             booking: %{reserved: 12, total: 41}
           } = line

    refute Map.has_key?(plain, :from_state)
  end

  test "the console reads one provider-change state: expired when the pass ended undecided" do
    pending = %{id: "c", state: "pending_approval", expired: false}

    assert AttentionItems.provider_change(pending).state == "pending_approval"
    assert AttentionItems.provider_change(%{pending | expired: true}).state == "expired"
    assert AttentionItems.provider_change(nil) == nil
  end
end
