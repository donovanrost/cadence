defmodule CadenceSimulator.Providers.DatabaseDynamics.Ranges do
  @moduledoc """
  The value range `DatabaseDynamics` generates for each telemetry item, taken from the
  catalog's monitoring limits when it has them.

  Limits are read as COSMOS-style thresholds (`"red_low"`, `"yellow_low"`, `"yellow_high"`,
  `"red_high"`). A monitoring policy carries them in one of two shapes:

  - `default_rules`: monitoring rules. cadence_yaml imports produce `:<`/`:>` comparisons
    (since 52afebc0); XTCE imports produce `:range` rules from StaticAlarmRanges;
  - `rules`: the raw limits map, which cadence_yaml catalogs imported before 52afebc0 carry.

  Severities map to colours: watch and warning are yellow; distress, critical and severe are
  red. When several rules state the same threshold, warning beats watch and critical beats
  distress and severe (the COSMOS-equivalent levels first), then the first rule wins.

  A `:range` rule states thresholds only where its meaning is unambiguous:

  - `outside: true` (the range is the acceptable band): `lower` is the low threshold and
    `upper` the high one;
  - otherwise the range is the alarm band. With only `lower` it guards the high side (alarm at
    or above `lower`), with only `upper` the low side. A band with both bounds doesn't say which
    side it guards, so it states nothing and the fallback applies.

  Each side of the range is the red threshold, else the yellow one, else the fallback range's
  bound (the item name's keyword range for floats, the encoding's range for integers).
  """

  import Bitwise

  @type limits :: %{optional(binary()) => number()}
  @type range :: {number(), number()}

  @float_range_keywords [
    {["temp"], {-40.0, 85.0}},
    {["voltage"], {0.0, 50.0}},
    {["current"], {-10.0, 10.0}},
    {["percent", "soc"], {0.0, 100.0}},
    {["rate"], {-5.0, 5.0}},
    {["angle", "roll", "pitch", "yaw"], {-180.0, 180.0}}
  ]

  # severity -> {colour, preference}; a lower preference wins a contested threshold.
  @severities %{
    "warning" => {"yellow", 0},
    "watch" => {"yellow", 1},
    "critical" => {"red", 0},
    "distress" => {"red", 1},
    "severe" => {"red", 2}
  }

  @doc "Limits per parameter id, from a lowered monitoring plan."
  @spec limits_by_parameter(map()) :: %{optional(binary()) => limits()}
  def limits_by_parameter(plan) do
    plan
    |> value(:policies, [])
    |> Map.new(&{value(&1, :parameter_id), policy_limits(&1)})
  end

  @doc "Thresholds a monitoring policy states, from `default_rules` or a legacy `rules` map."
  @spec policy_limits(map()) :: limits()
  def policy_limits(policy) do
    legacy =
      case value(policy, :rules) do
        %{} = rules -> rules
        _other -> %{}
      end

    Map.merge(legacy, limits_from_rules(value(policy, :default_rules, [])))
  end

  @doc "The float range for an item: its limits, else the keyword range for its name."
  @spec float_range(limits(), binary()) :: range()
  def float_range(limits, item_name) do
    bounded(bounds(limits), keyword_range(item_name))
  end

  @doc "The integer range for an item: its limits (rounded), else its encoding's range."
  @spec int_range(limits(), term(), boolean()) :: range()
  def int_range(limits, bit_size, signed) do
    {low, high} = bounds(limits)
    bounded({round_bound(low), round_bound(high)}, encoding_range(bit_size, signed))
  end

  # Rules that state no threshold (enumerations, equality, two-bounded alarm bands, unknown
  # severities, non-numeric bounds) are skipped.
  defp limits_from_rules(rules) when is_list(rules) do
    rules
    |> Enum.flat_map(&rule_thresholds/1)
    |> Enum.sort_by(fn {_threshold, _bound, preference} -> preference end)
    |> Enum.reduce(%{}, fn {threshold, bound, _preference}, limits ->
      Map.put_new(limits, threshold, bound)
    end)
  end

  defp limits_from_rules(_rules), do: %{}

  defp rule_thresholds(%{} = rule) do
    case Map.fetch(@severities, to_string(value(rule, :severity))) do
      {:ok, {colour, preference}} ->
        rule
        |> sides(to_string(value(rule, :kind)))
        |> Enum.filter(fn {_side, bound} -> is_number(bound) end)
        |> Enum.map(fn {side, bound} -> {colour <> "_" <> side, bound, preference} end)

      :error ->
        []
    end
  end

  defp rule_thresholds(_rule), do: []

  # {side, bound} pairs a rule states: "low" means values below the bound alarm.
  defp sides(rule, "comparison") do
    case to_string(value(rule, :operator)) do
      "<" -> [{"low", value(rule, :value)}]
      ">" -> [{"high", value(rule, :value)}]
      _other -> []
    end
  end

  defp sides(rule, "range") do
    lower = value(rule, :lower)
    upper = value(rule, :upper)

    cond do
      value(rule, :outside) in [true, "true"] -> [{"low", lower}, {"high", upper}]
      is_nil(upper) -> [{"high", lower}]
      is_nil(lower) -> [{"low", upper}]
      true -> []
    end
  end

  defp sides(_rule, _kind), do: []

  # Red before yellow on each side: red thresholds sit outside the yellow ones.
  defp bounds(limits) do
    {limits["red_low"] || limits["yellow_low"], limits["red_high"] || limits["yellow_high"]}
  end

  # A missing side takes the fallback's bound. A one-sided limit can land beyond the fallback's
  # other bound (a red_high under the keyword minimum); then the missing side is a fallback span
  # away, so low < high always holds.
  defp bounded({nil, nil}, fallback), do: fallback

  defp bounded({low, nil}, {_fallback_low, fallback_high} = fallback),
    do: {low, if(fallback_high > low, do: fallback_high, else: low + span(fallback))}

  defp bounded({nil, high}, {fallback_low, _fallback_high} = fallback),
    do: {if(fallback_low < high, do: fallback_low, else: high - span(fallback)), high}

  defp bounded({_low, _high} = limits, _fallback), do: limits

  defp span({low, high}), do: high - low

  defp round_bound(nil), do: nil
  defp round_bound(bound), do: round(bound)

  defp keyword_range(name) do
    Enum.find_value(@float_range_keywords, fn {keywords, range} ->
      if String.contains?(name, keywords), do: range, else: nil
    end) || {0.0, 100.0}
  end

  defp encoding_range(bit_size, signed) when is_integer(bit_size) and bit_size > 0 do
    max_val = (1 <<< bit_size) - 1

    if signed do
      half = div(max_val + 1, 2)
      {-half, half - 1}
    else
      {0, max_val}
    end
  end

  defp encoding_range(_bit_size, true), do: {-1000, 1000}
  defp encoding_range(_bit_size, false), do: {0, 1000}

  defp value(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
