defmodule Cadence.Catalog.MissionModelDiagnosticTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Diagnostic

  @cold_decode_probe Path.expand("../../support/mission_model_cold_decode_helper.exs", __DIR__)

  test "stored runtime plans decode before compiler modules have loaded in a fresh VM" do
    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2",
          "-pa",
          Application.app_dir(:cadence_catalog, "ebin"),
          @cold_decode_probe
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "MISSION_MODEL_COLD_DECODE_OK"
  end

  test "diagnostic fields accept only their own wire vocabulary, even for existing atoms" do
    for {field, invalid} <- [
          {:severity, :legalization},
          {:stage, :warning},
          {:target, :preserved},
          {:support, :algorithm}
        ],
        value <- [invalid, Atom.to_string(invalid), 42, %{}, nil],
        value != nil or field in [:severity, :stage] do
      assert_raise ArgumentError, ~r/unsupported diagnostic #{field}/, fn ->
        Diagnostic.new(Map.put(diagnostic(), field, value))
      end
    end

    unknown = "unknown_diagnostic_value_#{System.unique_integer([:positive])}"

    for field <- [:severity, :stage, :target, :support] do
      assert_raise ArgumentError, fn -> Diagnostic.new(Map.put(diagnostic(), field, unknown)) end
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "optional fields and compiler diagnostic blocking semantics survive decoding" do
    for severity <- [:info, :warning, :error] do
      original = Diagnostic.new(%{diagnostic() | severity: severity})

      decoded =
        original |> Map.from_struct() |> Jason.encode!() |> Jason.decode!() |> Diagnostic.new()

      assert decoded == original
      assert Diagnostic.blocking?(decoded) == (severity == :error)
    end
  end

  defp diagnostic do
    %{
      code: "MM_ALGORITHM_IMPLEMENTATION_UNSUPPORTED",
      severity: :warning,
      stage: :legalization,
      message: "Preserved declaration"
    }
  end
end
