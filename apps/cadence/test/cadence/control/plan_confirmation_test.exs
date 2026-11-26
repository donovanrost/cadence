defmodule Cadence.Control.PlanConfirmationTest do
  @moduledoc "Plan detail's execution summary (lead: K1/K2 headers, bookingStopped)."
  use ExUnit.Case, async: true

  alias Cadence.Control.PlanConfirmation

  defp item(state, reservation \\ "provider_reservation_x"),
    do: %{lifecycle_state: state, provider_reservation_id: reservation}

  test "nothing to count before execution" do
    assert PlanConfirmation.execution([]) == nil
  end

  test "counts by how far each booking got; requested = sent + never_sent" do
    items = [
      item(:reserved),
      item(:reserved),
      item(:uncertain),
      item(:rejected),
      # The provider failed or lost it after it was placed.
      item(:failed),
      # Failed before the provider call (expired snapshot): never sent.
      item(:failed, nil),
      item(:pending, nil),
      item(:requesting, nil)
    ]

    assert PlanConfirmation.execution(items) == %{
             requested: 8,
             sent: 5,
             confirmed: 2,
             uncertain: 1,
             rejected: 1,
             failed: 1,
             never_sent: 3
           }
  end

  describe "bookings/1 (K1 8e)" do
    @at ~U[2026-11-13 01:00:00.000000Z]

    defp booking_item(id, state, reservation, error \\ %{}, times \\ %{}) do
      Map.merge(
        %{
          contact_opportunity_snapshot_id: id,
          lifecycle_state: state,
          provider_reservation_id: reservation,
          last_error_document: error,
          started_at: nil,
          completed_at: nil,
          updated_at: @at
        },
        times
      )
    end

    test "per-pass states add up to the execution counts" do
      items = [
        booking_item("s1", :reserved, "r1", %{}, %{completed_at: DateTime.add(@at, 5)}),
        booking_item("s2", :uncertain, "r2", %{"code" => "provider_timeout"}),
        booking_item("s3", :rejected, "r3", %{"reason" => "rejected"}),
        booking_item("s4", :failed, "r4", %{"category" => "provider_configuration_failure"}),
        booking_item("s5", :failed, nil, %{"code" => "snapshot_expired"}),
        booking_item("s6", :pending, nil),
        booking_item("s7", :requesting, nil, %{}, %{started_at: DateTime.add(@at, 2)}),
        # A provider error (ProviderError.to_map) nests its normalized category.
        booking_item("s8", :rejected, "r8", %{
          "lifecycle_state" => "rejected",
          "reason" => %{
            "category" => "no_capacity",
            "detail" => "Station full",
            "retryable" => false
          }
        }),
        # A term the domain encoded as a tuple map has no code to show.
        booking_item("s9", :uncertain, "r9", %{"reason" => %{"tuple" => ["malformed", "status"]}})
      ]

      bookings = PlanConfirmation.bookings(items)

      core = Map.new(bookings, fn {id, b} -> {id, Map.take(b, [:state, :reason, :at])} end)

      assert core["s1"] == %{state: "confirmed", reason: nil, at: DateTime.add(@at, 5)}
      assert core["s2"] == %{state: "uncertain", reason: "provider_timeout", at: @at}
      assert core["s3"].state == "rejected" and core["s3"].reason == "rejected"
      assert core["s4"] == %{state: "failed", reason: "provider_configuration_failure", at: @at}
      assert core["s5"] == %{state: "never_sent", reason: "snapshot_expired", at: @at}
      assert core["s6"] == %{state: "never_sent", reason: nil, at: @at}
      assert core["s7"] == %{state: "never_sent", reason: "sending", at: DateTime.add(@at, 2)}
      assert core["s8"] == %{state: "rejected", reason: "no_capacity", at: @at}
      assert core["s9"] == %{state: "uncertain", reason: nil, at: @at}

      # The provider's own words and retry advice, when its error carried them.
      assert %{detail: "Station full", retryable: false, retry_after_seconds: nil} =
               bookings["s8"]

      assert %{detail: nil, retryable: nil, resolved: nil} = bookings["s6"]

      counts = PlanConfirmation.execution(items)
      states = bookings |> Map.values() |> Enum.frequencies_by(& &1.state)

      for state <- ~w(confirmed uncertain rejected failed never_sent)a do
        assert Map.get(states, Atom.to_string(state), 0) == Map.fetch!(counts, state)
      end
    end

    test "an operator's resolution names who and when (U29)" do
      item =
        booking_item("s10", :failed, "r10", %{
          "code" => "operator_not_booked",
          "resolved_by" => %{"kind" => "user", "id" => "user-1"},
          "resolved_at" => "2026-11-13T10:52:00Z"
        })

      assert %{reason: "operator_not_booked", resolved: resolved} =
               PlanConfirmation.bookings([item], member_names(%{"user-1" => "Mira K."}))["s10"]

      assert resolved == %{
               by: %{kind: "user", id: "user-1", name: "Mira K."},
               at: "2026-11-13T10:52:00Z"
             }

      # "Mark booked" carries the same, on a confirmed booking with no reason.
      attested =
        booking_item("s11", :reserved, "r11", %{
          "evidence" => "operator_attested",
          "resolved_by" => %{"kind" => "user", "id" => "user-1"},
          "resolved_at" => "2026-11-13T10:53:00Z"
        })

      assert %{
               state: "confirmed",
               reason: nil,
               detail: nil,
               resolved: %{at: "2026-11-13T10:53:00Z"}
             } =
               PlanConfirmation.bookings([attested], member_names(%{"user-1" => "Mira K."}))[
                 "s11"
               ]
    end
  end

  # ActorRef.names/2's shape for members of this organization (#468).
  defp member_names(users),
    do: %{
      users: users,
      user_ids: MapSet.new(Map.keys(users)),
      services: %{},
      service_ids: MapSet.new()
    }
end
