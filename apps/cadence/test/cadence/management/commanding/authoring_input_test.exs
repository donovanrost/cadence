defmodule Cadence.Management.Commanding.AuthoringInputTest do
  use ExUnit.Case, async: true

  alias Cadence.Management.Commanding.AuthoringInput

  defp input do
    %{
      "expected_basis" => String.duplicate("a", 64),
      "source_endpoint_ref" => "endpoint_one",
      "command_id" => "command:one",
      "argument_values_json" => "{}",
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }
  end

  test "preserves absent, false, zero, empty string and numeric versus string enumeration values" do
    arguments = %{"enabled" => false, "count" => 0, "label" => "", "mode" => 2, "code" => "2"}

    assert {:ok, admitted} =
             AuthoringInput.preview(
               Map.put(input(), "argument_values_json", Jason.encode!(arguments))
             )

    assert admitted.argument_values == arguments
    refute Map.has_key?(admitted.argument_values, "omitted")
    assert admitted.source_endpoint_ref == "endpoint_one"
    assert admitted.command_id == "command:one"
  end

  test "rejects injected authority, derived fields, unknown keys and route-like identifiers" do
    for key <- ["requested_by", "organization_id", "mission_id", "critical", "lifecycle_state"] do
      assert {:error, :invalid_command_authoring_input} =
               AuthoringInput.preview(Map.put(input(), key, "forged"))
    end

    for endpoint <- ["../other", "endpoint/other", "endpoint%2fother", "", nil] do
      assert {:error, :invalid_command_authoring_input} =
               AuthoringInput.preview(Map.put(input(), "source_endpoint_ref", endpoint))
    end

    assert {:ok, digest} =
             AuthoringInput.create(%{"expected_preview" => input()["expected_basis"]})

    assert digest == input()["expected_basis"]

    assert {:error, _} =
             AuthoringInput.create(%{"expected_preview" => digest, "command_id" => "other"})

    assert {:error, _} = AuthoringInput.create(%{"expected_preview" => String.upcase(digest)})
  end

  test "bounds count and encoded bytes, disallows nested values and admits exact wide integers" do
    for arguments <- [
          %{"x" => nil},
          %{"x" => [1]},
          %{"x" => %{"a" => 1}},
          %{"x" => String.duplicate("é", 16_384)},
          Map.new(1..65, &{"arg_#{&1}", &1})
        ] do
      assert {:error, _} =
               AuthoringInput.preview(
                 Map.put(input(), "argument_values_json", Jason.encode!(arguments))
               )
    end

    assert {:ok, _} =
             AuthoringInput.preview(
               Map.put(
                 input(),
                 "argument_values_json",
                 Jason.encode!(%{"x" => 18_446_744_073_709_551_615})
               )
             )

    assert {:ok, _} =
             AuthoringInput.preview(
               Map.put(
                 input(),
                 "argument_values_json",
                 Jason.encode!(Map.new(1..64, &{"arg_#{&1}", &1}))
               )
             )
  end

  test "admits exact UTC instants, enforces ordering and the database priority range" do
    valid =
      Map.merge(input(), %{
        "not_before" => "2026-09-10T10:00:00.123456Z",
        "expires_at" => "2026-09-10T10:00:00.123457Z",
        "priority" => 2_147_483_647
      })

    assert {:ok, admitted} = AuthoringInput.preview(valid)
    assert admitted.not_before == ~U[2026-09-10 10:00:00.123456Z]
    assert admitted.expires_at == ~U[2026-09-10 10:00:00.123457Z]
    assert {:error, _} = AuthoringInput.preview(Map.put(valid, "expires_at", valid["not_before"]))

    assert {:error, _} =
             AuthoringInput.preview(Map.put(valid, "not_before", "2026-09-10T10:00:00+01:00"))

    for priority <- [-1, 2_147_483_648, 1.2, "3"] do
      assert {:error, _} = AuthoringInput.preview(Map.put(input(), "priority", priority))
    end
  end

  test "old numeric maps, mixed contracts and duplicate JSON keys cannot enter authoring" do
    old = input() |> Map.delete("argument_values_json") |> Map.put("argument_values", %{"x" => 1})
    assert {:error, _} = AuthoringInput.preview(old)
    assert {:error, _} = AuthoringInput.preview(Map.put(input(), "argument_values", %{}))

    for text <- [~s({"x":1,"x":2}), ~s({"x":null}), "not json"] do
      assert {:error, _} = AuthoringInput.preview(Map.put(input(), "argument_values_json", text))
    end

    values = %{"unsigned" => 18_446_744_073_709_551_615, "signed" => -9_223_372_036_854_775_808}

    assert {:ok, admitted} =
             AuthoringInput.preview(
               Map.put(input(), "argument_values_json", Jason.encode!(values))
             )

    assert admitted.argument_values == values
  end
end
