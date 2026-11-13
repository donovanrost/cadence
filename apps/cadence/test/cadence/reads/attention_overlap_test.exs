defmodule Cadence.Reads.AttentionOverlapTest do
  @moduledoc "One row for one cause: an open activation_apply item carries a not-applied runtime."
  use ExUnit.Case, async: true

  alias Cadence.Reads.Attention

  @runtime %{id: "mission-1", source: "mission_runtime"}
  @apply %{id: "activation_request_1", source: "activation_apply"}
  @other %{id: "res-1", source: "pass_release"}

  test "an open activation_apply item replaces mission_runtime and says the runtime isn't applied" do
    assert [
             %{source: "activation_apply", runtime_not_applied: true},
             %{source: "pass_release"} = other
           ] = Attention.one_row_per_cause([@runtime, @apply, @other])

    refute Map.has_key?(other, :runtime_not_applied)
  end

  test "without a runtime item the activation item says the runtime is applied" do
    assert [%{runtime_not_applied: false}] = Attention.one_row_per_cause([@apply])
  end

  test "without an activation_apply item mission_runtime stays" do
    assert Attention.one_row_per_cause([@runtime, @other]) == [@runtime, @other]
  end
end
