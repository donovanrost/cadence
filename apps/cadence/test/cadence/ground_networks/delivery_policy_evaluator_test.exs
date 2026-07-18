defmodule Cadence.GroundNetworks.DeliveryPolicyEvaluatorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.GroundNetworks.{DeliveryPolicy, DeliveryPolicyEvaluator}

  test "classifies operational-only updates as observation" do
    result = evaluate(%{}, snapshot(), Map.put(snapshot(), "pass_phase", "pass"))

    assert result.decision == :observation
    assert result.changed_fields == ["pass_phase"]
  end

  test "requires approval by default for a material proposal" do
    current = shift(snapshot(), 1, 1)
    result = evaluate(%{}, snapshot(), current)

    assert result.decision == :approval_required
    assert "delivery_policy_requires_approval" in result.reasons
  end

  test "accepts changes exactly on inclusive timing boundaries" do
    policy = %{
      "mode" => "bounded_automatic",
      "maximum_later_start_shift_seconds" => 60,
      "maximum_later_end_shift_seconds" => 60
    }

    result = evaluate(policy, snapshot(), shift(snapshot(), 60, 60))
    assert result.decision == :policy_accept
  end

  test "requires approval one second outside a timing boundary" do
    policy = %{
      "mode" => "bounded_automatic",
      "maximum_later_start_shift_seconds" => 60,
      "maximum_later_end_shift_seconds" => 60
    }

    result = evaluate(policy, snapshot(), shift(snapshot(), 61, 60))
    assert result.decision == :approval_required
    assert "starts_at_later_shift_exceeds_policy" in result.reasons
  end

  test "honors station, equivalent-resource, capacity, duration, and cost bounds" do
    policy = %{
      "mode" => "bounded_automatic",
      "approved_station_substitutions" => ["station-b"],
      "approved_equivalent_resource_substitutions" => ["pool-a->pool-b"],
      "minimum_retained_duration_seconds" => 500,
      "minimum_retained_estimated_capacity_bytes" => 900,
      "maximum_cost_delta" => 10
    }

    current =
      snapshot()
      |> Map.put("ground_station_ref", "station-b")
      |> Map.put("antenna_or_service_pool_ref", "pool-b")
      |> put_in(["extensions", "estimated_capacity", "value"], 900)
      |> put_in(["extensions", "cost"], 110)

    assert evaluate(policy, snapshot(), current).decision == :policy_accept
  end

  test "fails conservatively when a policy input is missing" do
    policy = %{
      "mode" => "bounded_automatic",
      "minimum_retained_estimated_capacity_bytes" => 900
    }

    current = snapshot() |> Map.put("starts_at", nil) |> put_in(["extensions"], %{})
    result = evaluate(policy, snapshot(), current)

    assert result.decision == :approval_required
    assert "starts_at_shift_missing_or_invalid" in result.reasons
    assert "retained_capacity_missing_or_invalid" in result.reasons
  end

  test "configuration mismatch wins before tolerance evaluation" do
    policy = %{
      "mode" => "bounded_automatic",
      "maximum_later_start_shift_seconds" => 600
    }

    current = shift(snapshot(), 60, 60) |> Map.put("spacecraft_ref", "spacecraft-b")
    result = evaluate(policy, snapshot(), current)

    assert result.decision == :configuration_failure
    assert result.reasons == ["provider_contact_configuration_mismatch"]
  end

  test "counteroffers and disabled automatic revisions require approval" do
    counteroffer = put_in(snapshot(), ["extensions", "counteroffer"], %{"kind" => "timing"})

    assert evaluate(%{"mode" => "bounded_automatic"}, snapshot(), counteroffer).decision ==
             :approval_required

    result =
      evaluate(
        %{
          "mode" => "bounded_automatic",
          "allow_automatic_execution_revision" => false,
          "maximum_later_start_shift_seconds" => 60,
          "maximum_later_end_shift_seconds" => 60
        },
        snapshot(),
        shift(snapshot(), 10, 10)
      )

    assert result.decision == :approval_required
    assert "automatic_execution_revision_disabled" in result.reasons
  end

  test "already-effective changes and cancellation facts require acknowledgment" do
    effective =
      snapshot()
      |> shift(30, 30)
      |> Map.update!("extensions", &Map.put(&1, "provider_change", %{"effective" => true}))

    assert get_in(effective, ["extensions", "provider_change", "effective"])

    assert evaluate(%{}, snapshot(), effective).decision == :acknowledgment_required

    canceled = Map.put(snapshot(), "status", "canceled")
    assert evaluate(%{}, snapshot(), canceled).decision == :acknowledgment_required
  end

  test "immutable delivery configuration cannot be accepted from Contact data" do
    current = put_in(snapshot(), ["delivery_descriptor", "protocol"], "udp")
    result = evaluate(%{"mode" => "bounded_automatic"}, snapshot(), current)

    assert result.decision == :configuration_failure
  end

  defp evaluate(policy_document, before, current) do
    {:ok, policy} = DeliveryPolicy.normalize(policy_document)
    DeliveryPolicyEvaluator.evaluate(policy, before, current)
  end

  defp shift(snapshot, start_seconds, end_seconds) do
    snapshot
    |> Map.update!("starts_at", &shift_time(&1, start_seconds))
    |> Map.update!("ends_at", &shift_time(&1, end_seconds))
  end

  defp shift_time(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp snapshot do
    %{
      "provider_contact_ref" => "contact-1",
      "provider_revision" => 1,
      "client_reference" => "client-1",
      "opportunity_ref" => "opportunity-1",
      "spacecraft_ref" => "spacecraft-1",
      "ground_station_ref" => "station-a",
      "antenna_or_service_pool_ref" => "pool-a",
      "service_profile_ref" => "service-1",
      "delivery_profile_ref" => "delivery-1",
      "starts_at" => "2026-07-15T12:00:00Z",
      "ends_at" => "2026-07-15T12:10:00Z",
      "status" => "confirmed",
      "pass_phase" => "scheduled",
      "delivery_state" => "pending",
      "status_reason" => nil,
      "delivery_descriptor" => %{
        "direction" => "downlink",
        "delivery_kind" => "realtime_stream",
        "mode" => "provider_connects",
        "protocol" => "tcp",
        "endpoint_ref" => "delivery-1",
        "framing" => %{"family" => "ccsds_tm"},
        "credential_ref" => "credential-1",
        "allowed_source_refs" => ["spacecraft-1"]
      },
      "extensions" => %{
        "estimated_capacity" => %{"value" => 1_000, "unit" => "bytes"},
        "cost" => 100
      }
    }
  end
end
