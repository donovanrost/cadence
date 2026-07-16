defmodule Cadence.GroundNetworks.DeliveryPolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.GroundNetworks.DeliveryPolicy

  test "defaults to explicit approval and round-trips its complete document" do
    assert {:ok, policy} = DeliveryPolicy.normalize(%{})
    assert policy.mode == :approval_required
    assert policy.version == 1
    assert policy.allow_automatic_execution_revision

    assert {:ok, ^policy} = policy |> DeliveryPolicy.to_document() |> DeliveryPolicy.normalize()
  end

  test "accepts the bounded automatic policy fields used by mission setup" do
    assert {:ok, policy} =
             DeliveryPolicy.normalize(%{
               "version" => 4,
               "mode" => "bounded_automatic",
               "maximum_earlier_start_shift_seconds" => 60,
               "maximum_later_start_shift_seconds" => 120,
               "maximum_earlier_end_shift_seconds" => 30,
               "maximum_later_end_shift_seconds" => 90,
               "minimum_retained_duration_seconds" => 300,
               "minimum_retained_estimated_capacity_bytes" => 1_000,
               "approved_station_substitutions" => ["station-b"],
               "approved_equivalent_resource_substitutions" => ["pool-a->pool-b"],
               "maximum_cost_delta" => 25.5,
               "changes_always_requiring_approval" => ["cancellation"],
               "deadline_behavior" => "cancel_if_actionable",
               "allow_automatic_execution_revision" => false,
               "extensions" => %{"owner" => "flight"}
             })

    assert policy.version == 4
    assert policy.mode == :bounded_automatic
    refute policy.allow_automatic_execution_revision
  end

  test "rejects unknown fields and unknown approval categories" do
    assert {:error, {:unknown_delivery_policy_field, "surprise"}} =
             DeliveryPolicy.normalize(%{"surprise" => true})

    assert {:error, {:unknown_delivery_policy_category, "routing"}} =
             DeliveryPolicy.normalize(%{
               "changes_always_requiring_approval" => ["routing"]
             })
  end

  test "rejects malformed or negative tolerance values" do
    assert {:error, {:invalid_delivery_policy_field, "maximum_cost_delta"}} =
             DeliveryPolicy.normalize(%{"maximum_cost_delta" => -1})

    assert {:error, {:invalid_delivery_policy_field, "maximum_later_start_shift_seconds"}} =
             DeliveryPolicy.normalize(%{"maximum_later_start_shift_seconds" => "60"})
  end
end
