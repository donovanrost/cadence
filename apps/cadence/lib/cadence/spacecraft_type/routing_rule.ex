defmodule Cadence.SpacecraftType.RoutingRule do
  @moduledoc """
  A routing rule on a Spacecraft Profile version (DECISIONS #3,
  `docs/apogee/domain/profile-routing.md` §2.1): for each spacecraft on the profile and each
  station in the rule, route these legs, named by a template.

      %{"id" => "ttc",
        "label" => "TT&C",
        "name_template" => "{station} · {spacecraft}",
        "enabled" => true,
        "stations" => [%{"ground_station_id" => "svalbard", "transport_id" => nil}],
        "legs" => [%{"direction" => "downlink", "role" => "primary"}]}

  A station's `transport_id` is optional; when it is absent, the station's single active
  transport compatible with the legs is used. This module checks shape only; stations and
  transports are resolved by the comms route materializer.
  """

  alias Cadence.Ids

  @directions ~w(downlink uplink)
  @roles ~w(primary candidate contributing)
  @tokens ~w(station station_name spacecraft scid direction)
  @default_template "{station} · {spacecraft}"
  @max_rules 32
  @max_stations 64

  @type t :: map()
  @type error :: %{path: String.t(), message: String.t()}

  def directions, do: @directions
  def roles, do: @roles
  def tokens, do: @tokens

  @doc "Normalizes a profile's rule list. Paths in errors are `routing_rules.<index>.<field>`."
  @spec normalize(term()) :: {:ok, [t()]} | {:error, [error()]}
  def normalize(nil), do: {:ok, []}

  def normalize(rules) when is_list(rules) and length(rules) <= @max_rules do
    normalized = rules |> Enum.with_index() |> Enum.map(fn {rule, i} -> rule(rule, i) end)
    errors = Enum.flat_map(normalized, &elem(&1, 1)) ++ duplicate_ids(normalized)

    if errors == [], do: {:ok, Enum.map(normalized, &elem(&1, 0))}, else: {:error, errors}
  end

  def normalize(_rules),
    do: {:error, [error("routing_rules", "List up to #{@max_rules} routing rules")]}

  @doc "Renders a route name. Unknown values render as empty strings."
  @spec render_name(String.t(), map()) :: String.t()
  def render_name(template, values) do
    @tokens
    |> Enum.reduce(template, fn token, acc ->
      String.replace(acc, "{#{token}}", to_string(Map.get(values, token, "")))
    end)
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp rule(%{} = rule, i) do
    rule = %{
      "id" => Map.get(rule, "id") || Ids.new("profile_rule"),
      "label" => Map.get(rule, "label") || "TT&C",
      "name_template" => Map.get(rule, "name_template") || @default_template,
      "enabled" => Map.get(rule, "enabled", true),
      "stations" => Map.get(rule, "stations", []),
      "legs" => Map.get(rule, "legs", [])
    }

    errors =
      id_errors(rule["id"], i) ++
        label_errors(rule["label"], i) ++
        template_errors(rule["name_template"], i) ++
        bool_errors(rule["enabled"], i) ++
        station_errors(rule["stations"], i) ++ leg_errors(rule["legs"], i)

    {Map.update!(rule, "stations", &normalize_stations/1), errors}
  end

  defp rule(_rule, i), do: {%{}, [error("routing_rules.#{i}", "Must be an object")]}

  defp id_errors(id, i) do
    if Ids.valid_identifier?(id), do: [], else: [error("routing_rules.#{i}.id", "Invalid id")]
  end

  defp label_errors(label, _i) when is_binary(label) and byte_size(label) in 1..120, do: []
  defp label_errors(_label, i), do: [error("routing_rules.#{i}.label", "Enter a short label")]

  defp template_errors(template, i) when is_binary(template) and byte_size(template) in 1..200 do
    unknown =
      ~r/\{([^}]*)\}/
      |> Regex.scan(template, capture: :all_but_first)
      |> List.flatten()
      |> Enum.reject(&(&1 in @tokens))

    case unknown do
      [] -> []
      [token | _] -> [error("routing_rules.#{i}.name_template", "Unknown token {#{token}}")]
    end
  end

  defp template_errors(_template, i),
    do: [error("routing_rules.#{i}.name_template", "Enter a name template")]

  defp bool_errors(value, _i) when is_boolean(value), do: []
  defp bool_errors(_value, i), do: [error("routing_rules.#{i}.enabled", "Must be true or false")]

  defp station_errors(stations, i)
       when is_list(stations) and length(stations) in 1..@max_stations do
    ids = Enum.map(stations, &station_id/1)

    cond do
      Enum.any?(ids, &(not Ids.valid_identifier?(&1))) ->
        [error("routing_rules.#{i}.stations", "Choose stations")]

      length(Enum.uniq(ids)) != length(ids) ->
        [error("routing_rules.#{i}.stations", "Each station appears once")]

      true ->
        []
    end
  end

  defp station_errors(_stations, i),
    do: [error("routing_rules.#{i}.stations", "Choose 1–#{@max_stations} stations")]

  defp leg_errors(legs, i) when is_list(legs) and length(legs) in 1..2 do
    valid? =
      Enum.all?(legs, fn leg ->
        is_map(leg) and leg["direction"] in @directions and
          Map.get(leg, "role", "primary") in @roles
      end)

    directions = Enum.map(legs, &(is_map(&1) && &1["direction"]))

    cond do
      not valid? ->
        [error("routing_rules.#{i}.legs", "Each leg needs a direction and role")]

      length(Enum.uniq(directions)) != length(directions) ->
        [error("routing_rules.#{i}.legs", "One leg per direction")]

      true ->
        []
    end
  end

  defp leg_errors(_legs, i),
    do: [error("routing_rules.#{i}.legs", "Add a downlink or uplink leg")]

  defp normalize_stations(stations) when is_list(stations) do
    Enum.map(stations, fn station ->
      %{"ground_station_id" => station_id(station), "transport_id" => station_transport(station)}
    end)
  end

  defp normalize_stations(other), do: other

  defp station_id(%{"ground_station_id" => id}), do: id
  defp station_id(_station), do: nil

  defp station_transport(%{"transport_id" => id}) when is_binary(id), do: id
  defp station_transport(_station), do: nil

  defp duplicate_ids(normalized) do
    ids = Enum.map(normalized, fn {rule, _} -> rule["id"] end)

    if length(Enum.uniq(ids)) == length(ids),
      do: [],
      else: [error("routing_rules", "Each rule needs its own id")]
  end

  defp error(path, message), do: %{path: path, message: message}
end
