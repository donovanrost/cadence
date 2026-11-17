defmodule Cadence.Catalog.Importers.Xtce13.Calibration do
  @moduledoc """
  A parameter type's calibration and states, read from XTCE 1.3 the way the Cadence YAML importer
  reads `conversion` (DECISIONS #92 (c)).

  - **Calibrators** (`calibrators/1`): the encoding's `DefaultCalibrator` and each
    `ContextCalibrator`. A polynomial executes at decom (telemetry contract 3). A spline, a math
    operation or a context calibrator is still declared, so target legalization reports it
    (`MM_CALIBRATOR_RUNTIME_UNSUPPORTED`) instead of the import dropping it. A context calibrator
    doesn't execute, so the default calibrator applies whatever the context.
  - **States** (`enumerations/1`): `EnumerationList` as `[%{value, label}]` in source order. A
    `maxValue` range expands to one state per value, up to 256 values.

  Both return their diagnostics as `{code, message, element}`; the translator places them.
  """

  alias XTCE.Element

  @max_degree 16
  @max_range 256

  @type calibrator :: %{
          role: :calibrator | :context_calibrator,
          suffix: binary(),
          definition: map(),
          element: Element.t()
        }
  @type issue :: {binary(), binary(), Element.t()}

  @doc "The type's calibrator declarations to make, and what couldn't be read."
  @spec calibrators(Element.t()) :: {[calibrator()], [issue()]}
  def calibrators(%Element{} = type_element) do
    case data_encoding(type_element) do
      nil -> {[], []}
      encoding -> encoding_calibrators(encoding)
    end
  end

  @doc "The type's states as `[%{value, label}]`, and what couldn't be read."
  @spec enumerations(Element.t()) :: {[map()], [issue()]}
  def enumerations(%Element{} = type_element) do
    case Element.child(type_element, "EnumerationList") do
      nil ->
        {[], []}

      list ->
        list
        |> Element.children("Enumeration")
        |> Enum.map(&states/1)
        |> Enum.reduce({[], []}, fn {states, issues}, {all, all_issues} ->
          {all ++ states, all_issues ++ issues}
        end)
    end
  end

  defp states(enumeration) do
    label = Element.attr(enumeration, "label")
    first = integer(Element.attr(enumeration, "value"))
    last = integer(Element.attr(enumeration, "maxValue"))

    cond do
      # Not an integer: kept with a nil value, so legalization says it never matches.
      is_nil(first) or is_nil(last) or last == first ->
        {[%{value: first, label: label}], []}

      last > first and last - first < @max_range ->
        {Enum.map(first..last, &%{value: &1, label: label}), []}

      true ->
        {[%{value: first, label: label}],
         [
           {"XTCE_ENUMERATION_RANGE_UNSUPPORTED",
            "state #{inspect(label)} covers #{first}..#{last}; only #{first} is mapped " <>
              "(ranges up to #{@max_range} values expand)", enumeration}
         ]}
    end
  end

  defp encoding_calibrators(encoding) do
    default =
      case Element.child(encoding, "DefaultCalibrator") do
        nil -> {[], []}
        calibrator -> calibrator(calibrator, :calibrator, "default")
      end

    contexts =
      encoding
      |> Element.child("ContextCalibratorList")
      |> context_calibrators()

    [default | contexts]
    |> Enum.reduce({[], []}, fn {calibrators, issues}, {all, all_issues} ->
      {all ++ calibrators, all_issues ++ issues}
    end)
  end

  defp context_calibrators(nil), do: []

  defp context_calibrators(list) do
    list
    |> Element.children("ContextCalibrator")
    |> Enum.with_index(1)
    |> Enum.map(fn {context, index} ->
      inner = Element.child(context, "Calibrator")
      kind = inner && inner |> implementation() |> then(&(&1 && &1.name))

      {[
         %{
           role: :context_calibrator,
           suffix: "context_#{index}",
           definition: %{algorithm_type: :context, calibrator: kind, required: false},
           element: context
         }
       ], []}
    end)
  end

  defp calibrator(calibrator, role, suffix) do
    case implementation(calibrator) do
      %Element{name: "PolynomialCalibrator"} = polynomial ->
        polynomial(polynomial, role, suffix)

      %Element{name: "SplineCalibrator"} = spline ->
        {[
           %{
             role: role,
             suffix: suffix,
             definition: %{
               algorithm_type: :spline,
               order: integer(Element.attr(spline, "order")) || 1,
               extrapolate: Element.attr(spline, "extrapolate") == "true",
               points:
                 for point <- Element.children(spline, "SplinePoint") do
                   %{
                     raw: numeric(Element.attr(point, "raw")),
                     calibrated: numeric(Element.attr(point, "calibrated"))
                   }
                 end,
               required: false
             },
             element: spline
           }
         ], []}

      %Element{name: name} = other ->
        {[
           %{
             role: role,
             suffix: suffix,
             definition: %{
               algorithm_type: :math_operation,
               xtce_calibrator: name,
               required: false
             },
             element: other
           }
         ], []}

      nil ->
        {[], []}
    end
  end

  # Coefficients lowest order first, an exponent named twice summed, a missing one 0.0.
  defp polynomial(polynomial, role, suffix) do
    terms =
      for term <- Element.children(polynomial, "Term") do
        {integer(Element.attr(term, "exponent")), numeric(Element.attr(term, "coefficient"))}
      end

    degree = terms |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> nil end)

    cond do
      terms == [] or
          Enum.any?(terms, fn {exponent, coefficient} ->
            not is_integer(exponent) or exponent < 0 or not is_float(coefficient)
          end) ->
        {[],
         [
           {"XTCE_CALIBRATOR_INVALID",
            "polynomial calibrator has a term without a numeric coefficient and exponent; " <>
              "the parameter stays uncalibrated", polynomial}
         ]}

      degree > @max_degree ->
        {[],
         [
           {"XTCE_CALIBRATOR_DEGREE_UNSUPPORTED",
            "polynomial calibrator of degree #{degree} is above #{@max_degree}; " <>
              "the parameter stays uncalibrated", polynomial}
         ]}

      true ->
        sums = Enum.reduce(terms, %{}, fn {e, c}, acc -> Map.update(acc, e, c, &(&1 + c)) end)

        {[
           %{
             role: role,
             suffix: suffix,
             definition: %{
               algorithm_type: :polynomial,
               coefficients: for(e <- 0..degree, do: Map.get(sums, e, 0.0)),
               required: false
             },
             element: polynomial
           }
         ], []}
    end
  end

  defp implementation(calibrator),
    do: Enum.find(calibrator.children, &String.ends_with?(&1.name, "Calibrator"))

  defp data_encoding(type_element),
    do: Enum.find(type_element.children, &String.ends_with?(&1.name, "DataEncoding"))

  defp numeric(nil), do: nil

  defp numeric(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp integer(nil), do: nil

  defp integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end
end
