defmodule Cadence.Telemetry.CalibrationTest do
  @moduledoc "A field's engineering value from its raw value (DECISIONS #92 (c))."
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{Calibration, FieldDefinition}

  defp field(attrs), do: FieldDefinition.new(Map.merge(%{name: "f", size_bits: 16}, attrs))

  describe "a polynomial calibrator" do
    test "evaluates c0 + c1·raw + c2·raw² + …, lowest order first" do
      assert Calibration.polynomial_value([5], 123) == {:ok, 5}
      assert Calibration.polynomial_value([-40.0, 0.01], 6000) == {:ok, 20.0}
      assert Calibration.polynomial_value([1, 2, 3], 2) == {:ok, 17}
      assert Calibration.polynomial_value([0.5, 0.0, 0.25], -4) == {:ok, 4.5}
    end

    test "the demo catalog's temperature sensor: 6000 counts are 20 °C" do
      outcome =
        Calibration.apply(
          field(%{calibrator: %{"type" => "polynomial", "coefficients" => [-40.0, 0.01]}}),
          6000
        )

      assert %{engineering_value: 20.0, quality_state: :good} = outcome
      assert outcome.calibration == %{"kind" => "polynomial", "coefficients" => [-40.0, 0.01]}
    end

    test "a raw value that isn't a number keeps the raw value, quality bad" do
      assert %{
               engineering_value: "x",
               quality_state: :bad,
               calibration: %{"reason" => "raw_not_numeric"}
             } =
               Calibration.apply(
                 field(%{calibrator: %{type: :polynomial, coefficients: [0, 1]}}),
                 "x"
               )
    end

    test "a result too large to store keeps the raw value, quality bad, never a non-finite number" do
      assert %{
               engineering_value: 10,
               quality_state: :bad,
               calibration: %{"reason" => "polynomial_not_finite"}
             } =
               Calibration.apply(
                 field(%{calibrator: %{type: :polynomial, coefficients: [0, 1.0e299]}}),
                 10
               )
    end
  end

  describe "enumerations (a state table)" do
    @states [%{value: 0, label: "SAFE"}, %{value: 4, label: "NOMINAL"}]

    test "a defined state reads its label" do
      assert %{
               engineering_value: "NOMINAL",
               quality_state: :good,
               calibration: %{"kind" => "enumeration"}
             } =
               Calibration.apply(field(%{enumerations: @states}), 4)
    end

    test "an undefined state keeps the raw state, quality suspect" do
      assert %{
               engineering_value: 7,
               quality_state: :suspect,
               calibration: %{"reason" => "state_not_defined"}
             } =
               Calibration.apply(field(%{enumerations: @states}), 7)
    end

    test "a raw value that isn't an integer keeps the raw value, quality bad" do
      assert %{engineering_value: 4.5, quality_state: :bad} =
               Calibration.apply(field(%{enumerations: @states}), 4.5)
    end
  end

  test "no calibration (every contract-2 plan): engineering is raw, no provenance" do
    assert Calibration.apply(field(%{}), 42) ==
             %{engineering_value: 42, quality_state: :good, calibration: nil}
  end

  test "a malformed calibrator or enumeration is refused when the plan decodes" do
    assert_raise ArgumentError, fn -> field(%{calibrator: %{type: :spline, points: []}}) end

    assert_raise ArgumentError, fn ->
      field(%{calibrator: %{type: :polynomial, coefficients: []}})
    end

    assert_raise ArgumentError, fn -> field(%{enumerations: [%{value: "4", label: "X"}]}) end
  end
end
