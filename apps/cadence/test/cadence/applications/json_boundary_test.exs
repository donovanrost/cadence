defmodule Cadence.Applications.JSONBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.JSONBoundary

  test "preserves valid values while safe normalizes keys for transport" do
    value = %{application: "alpha", values: [nil, true, 7, 1.5]}

    assert :ok = JSONBoundary.validate(value)

    assert {:ok, %{"application" => "alpha", "values" => [nil, true, 7, 1.5]}} =
             JSONBoundary.safe(value)
  end

  test "rejects unsupported scalar types and invalid keys" do
    assert {:error, :unsupported} = JSONBoundary.validate(%{"pid" => self()})
    assert {:error, :unsupported} = JSONBoundary.validate(%{"atom" => :not_json})
    assert {:error, :key} = JSONBoundary.validate(%{{:tuple_key, :second} => "value"})
  end

  test "rejects exact string, map, list, and document bounds" do
    assert {:error, :string} = JSONBoundary.validate(String.duplicate("s", 241))
    assert {:error, :map_items} = JSONBoundary.validate(Map.new(1..65, &{"key-#{&1}", &1}))
    assert {:error, :list_items} = JSONBoundary.validate(Enum.to_list(1..101))

    oversized_document =
      Map.new(1..64, fn index ->
        {"key-#{index}", Enum.map(1..100, fn _item -> String.duplicate("x", 10) end)}
      end)

    assert {:error, :document_bytes} = JSONBoundary.validate(oversized_document)
  end

  test "rejects values deeper than the recursive boundary" do
    assert :ok = JSONBoundary.validate(nested_map(8))
    assert {:error, :depth} = JSONBoundary.validate(nested_map(9))
  end

  test "allows richer Phoenix-owned output without relaxing request admission" do
    assert {:error, :depth} = JSONBoundary.safe(nested_map(9))
    assert {:ok, _safe} = JSONBoundary.safe_trusted_output(nested_map(12))
    assert {:error, :depth} = JSONBoundary.safe_trusted_output(nested_map(13))

    trusted_diagnostics = String.duplicate("d", 4_096)

    assert {:error, :string} = JSONBoundary.safe(trusted_diagnostics)
    assert {:ok, ^trusted_diagnostics} = JSONBoundary.safe_trusted_output(trusted_diagnostics)
    assert {:error, :string} = JSONBoundary.safe_trusted_output(trusted_diagnostics <> "d")
  end

  test "workflow output bounds do not widen generic input or legacy output" do
    long = String.duplicate("界", 2_730)
    assert {:ok, ^long} = JSONBoundary.safe_workflow_output(long)
    assert {:error, :string} = JSONBoundary.safe(long)
    assert {:error, :string} = JSONBoundary.safe_trusted_output(long)
    assert {:error, :string} = JSONBoundary.safe_workflow_output(long <> "界")
    assert {:ok, _} = JSONBoundary.safe_workflow_output(nested_map(16))
    assert {:error, :depth} = JSONBoundary.safe_workflow_output(nested_map(17))
    assert {:error, :unsupported} = JSONBoundary.safe_workflow_output(self())
    assert {:error, :list_items} = JSONBoundary.safe_workflow_output(Enum.to_list(1..101))
    oversized = Map.new(1..2, &{to_string(&1), List.duplicate(String.duplicate("x", 8_192), 100)})
    assert {:error, :document_bytes} = JSONBoundary.safe_workflow_output(oversized)
  end

  test "native planning input declares exact text wrappers and retains strict evidence bounds" do
    alias Cadence.Applications.OpsConsole.Actions.NativePlanningInput
    token = String.duplicate("t", 8_192)
    assert {:ok, %{"token" => ^token}} = NativePlanningInput.admit(%{"token" => token})
    assert {:error, _} = NativePlanningInput.admit(%{"token" => token <> "t"})
    assert {:error, _} = NativePlanningInput.admit(%{"token" => token, "extra" => true})
    reason = String.duplicate("界", 1_365)

    input = %{
      "contact_plan_id" => "plan",
      "plan_evidence" => %{"id" => "review"},
      "decision" => %{"reason" => reason}
    }

    assert {:ok, ^input} = NativePlanningInput.admit(input)

    assert {:error, _} =
             NativePlanningInput.admit(put_in(input, ["decision", "reason"], reason <> "界"))

    assert {:error, _} =
             NativePlanningInput.admit(
               put_in(input, ["plan_evidence", "id"], String.duplicate("x", 241))
             )

    assert {:error, _} = NativePlanningInput.admit(%{"untyped" => reason})
  end

  defp nested_map(0), do: %{}
  defp nested_map(depth), do: %{"next" => nested_map(depth - 1)}
end
