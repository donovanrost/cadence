defmodule Cadence.Contacts.PassResults.OutcomeTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.PassResults.Outcome

  @aos ~U[2026-11-09 12:00:00Z]
  @los ~U[2026-11-09 12:10:00Z]

  defp input(overrides) do
    Map.merge(
      %{
        lifecycle_state: :completed,
        cancel_initiator: :provider,
        planned_aos: @aos,
        planned_los: @los,
        result: nil,
        status_reason: nil,
        station_window: nil,
        threshold: 0.95,
        received_frames: nil,
        now: ~U[2026-11-09 13:00:00Z]
      },
      Map.new(overrides)
    )
  end

  defp result(aos_offset, los_offset, overrides \\ %{}) do
    Map.merge(
      %{
        "actual_acquisition_at" => DateTime.to_iso8601(DateTime.add(@aos, aos_offset)),
        "actual_loss_at" => DateTime.to_iso8601(DateTime.add(@aos, los_offset)),
        "bytes_delivered" => 1_000,
        "frames_delivered" => 10
      },
      overrides
    )
  end

  describe "cancellations (DECISIONS #47)" do
    test "Cadence-requested before AOS is canceled and not disputable" do
      assert %{outcome: "canceled", owner: "us", disputable: false} =
               Outcome.derive(
                 input(
                   lifecycle_state: :canceled,
                   cancel_initiator: :cadence,
                   now: ~U[2026-11-09 11:00:00Z]
                 )
               )
    end

    test "provider-initiated is a disputable miss" do
      assert %{outcome: "missed", cause: "provider_canceled", owner: "provider", disputable: true} =
               Outcome.derive(input(lifecycle_state: :canceled))

      assert %{outcome: "missed", cause: "provider_rejected"} =
               Outcome.derive(input(lifecycle_state: :rejected))
    end

    test "a provider reason naming weather is owned by weather" do
      assert %{outcome: "missed", owner: "weather", disputable: false} =
               Outcome.derive(
                 input(lifecycle_state: :canceled, status_reason: "Heavy rain (weather)")
               )
    end
  end

  describe "with a provider result" do
    test "flown at or above the threshold with delivery is realized" do
      assert %{outcome: "realized"} = Outcome.derive(input(result: result(0, 590)))
    end

    test "flown below the threshold is partial" do
      assert %{outcome: "partial", cause: "short_pass", owner: "provider"} =
               Outcome.derive(input(result: result(0, 300)))
    end

    test "delivered but nothing received by Cadence is partial, owned by us" do
      assert %{outcome: "partial", cause: "not_ingested", owner: "us"} =
               Outcome.derive(input(result: result(0, 600), received_frames: 0))

      assert %{outcome: "realized"} =
               Outcome.derive(input(result: result(0, 600), received_frames: nil))
    end

    test "no acquisition is missed; a named delivery failure is failed" do
      assert %{outcome: "missed", cause: "no_acquisition"} =
               Outcome.derive(input(result: %{"actual_acquisition_at" => nil}))

      assert %{outcome: "failed", cause: "tcp_refused", cause_source: "delivery"} =
               Outcome.derive(
                 input(
                   result: %{
                     "actual_acquisition_at" => nil,
                     "delivery_failure_reason" => "tcp_refused"
                   }
                 )
               )
    end

    test "a miss under a station window is owned by whoever reported it" do
      miss = %{"actual_acquisition_at" => nil}

      assert %{cause: "station_unavailable", owner: "us"} =
               Outcome.derive(input(result: miss, station_window: %{source: :operator}))

      assert %{cause: "station_unavailable", owner: "provider", disputable: true} =
               Outcome.derive(input(result: miss, station_window: %{source: :provider}))
    end
  end

  test "no provider result yet is pending_report" do
    assert %{outcome: "pending_report", disputable: false} = Outcome.derive(input([]))
  end
end
