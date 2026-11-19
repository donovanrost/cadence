defmodule Cadence.Control.ModelApprovalGateTest do
  @moduledoc "What a generation introduces, per (revision, spacecraft) (director 11-15)."
  use ExUnit.Case, async: true

  alias Cadence.Control.ModelApprovalGate

  defp on(revision), do: %{"mission_model" => %{"revision_id" => revision}}

  test "a spacecraft already on a revision keeps it; moving another one onto it introduces it" do
    running = %{"a" => on("x"), "b" => on("y")}
    entries = %{"a" => on("x"), "b" => on("x")}

    assert ModelApprovalGate.introduced(entries, running) == %{
             "x" => %{spacecraft_ids: ["b"], baselines: ["y"]}
           }
  end

  test "a new spacecraft introduces its revision with no baseline" do
    assert ModelApprovalGate.introduced(%{"c" => on("x")}, %{"a" => on("x")}) == %{
             "x" => %{spacecraft_ids: ["c"], baselines: [nil]}
           }
  end

  test "a legacy mission-wide generation is every spacecraft's baseline" do
    running = %{"__mission__" => on("m")}

    assert ModelApprovalGate.introduced(%{"a" => on("m"), "b" => on("n")}, running) == %{
             "n" => %{spacecraft_ids: ["b"], baselines: ["m"]}
           }
  end

  test "entries without a model introduce nothing" do
    assert ModelApprovalGate.introduced(%{"a" => %{}}, %{}) == %{}
  end
end
