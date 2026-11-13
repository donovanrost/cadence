defmodule Cadence.Dashboards.AuthoringInput do
  @moduledoc "Bounded command shapes for dashboard authoring, independent of frontend delivery."
  alias Cadence.Dashboards.PlacementEditor
  @widget_keys PlacementEditor.form_defaults() |> Map.delete("point_q") |> Map.keys()
  @boolean_fields ~w(show_unit show_min_max_band span_gaps show_points shared_tooltip)
  @integer_fields ~w(precision window_seconds fill_opacity repeat_max_instances)
  @enums %{
    "type" =>
      ~w(value_tile time_series status_matrix data_table state_timeline event_timeline constellation_health),
    "mode" => ~w(context fixed scope repeat),
    "binding_source" => ~w(telemetry limits operational_observables events),
    "legend_mode" => ~w(auto always hidden),
    "line_width" => ~w(thin normal bold),
    "axis_mode" => ~w(unit shared),
    "repeat_over" => ~w(spacecraft contact ground_station transport link),
    "repeat_layout" => ~w(wrap_grid row column)
  }

  def admit(event, %{"expected_version" => version} = input)
      when is_integer(version) and version in 1..9_007_199_254_740_990 do
    payload = Map.delete(input, "expected_version")
    if valid_payload?(event, payload), do: {:ok, version, payload}, else: {:error, :invalid_input}
  end

  def admit(_, _), do: {:error, :invalid_input}

  def text?(value, max), do: is_binary(value) and byte_size(value) <= max and String.valid?(value)
  def id?(value), do: text?(value, 256) and value != ""

  def widget_fields?(fields) when is_map(fields) do
    exact?(fields, @widget_keys) and
      Enum.all?(fields, fn {_key, value} -> text?(value, 512) end) and
      Enum.all?(@boolean_fields, &(fields[&1] in ~w(true false))) and
      Enum.all?(@integer_fields, &integer_text?(fields[&1])) and
      Enum.all?(@enums, fn {key, values} -> fields[key] in values end) and
      fields["scope_kind"] in [
        "" | ~w(mission spacecraft contact ground_station source_endpoint transport link)
      ]
  end

  def widget_fields?(_), do: false

  defp valid_payload?("rename", %{"name" => name, "description" => description} = input),
    do:
      map_size(input) == 2 and text?(name, 512) and String.trim(name) != "" and
        text?(description, 4096)

  defp valid_payload?("add_section", input), do: section?(input, false)
  defp valid_payload?("update_section", input), do: section?(input, true)

  defp valid_payload?("remove_section", %{"section_id" => id} = input),
    do: map_size(input) == 1 and id?(id)

  defp valid_payload?("move_section", %{"section_id" => id, "direction" => direction} = input),
    do: map_size(input) == 2 and id?(id) and direction in ~w(up down)

  defp valid_payload?("add_widget", input), do: widget?(input, false)

  # Places a library item's version by reference (the library plan's add_library_widget).
  defp valid_payload?(
         "add_library_widget",
         %{"placement_id" => placement, "library_item_id" => item, "version" => version} = input
       ),
       do:
         map_size(input) == 4 and client_id?(placement, "dash_widget_") and id?(item) and
           is_integer(version) and version in 1..9_007_199_254_740_990 and
           (input["section_id"] == "" or id?(input["section_id"]))

  defp valid_payload?("update_widget", input), do: widget?(input, true)

  defp valid_payload?("remove_widget", %{"placement_id" => id} = input),
    do: map_size(input) == 1 and id?(id)

  defp valid_payload?("layout", %{"layouts" => layouts} = input) when is_list(layouts),
    do:
      map_size(input) == 1 and length(layouts) in 1..1024 and
        Enum.all?(layouts, &layout?/1) and unique?(Enum.map(layouts, & &1["placement_id"]))

  defp valid_payload?("publish", input), do: input == %{}

  defp valid_payload?("runtime_defaults", %{"defaults_json" => json} = input),
    do: map_size(input) == 1 and text?(json, 32_768)

  defp valid_payload?(_, _), do: false

  defp section?(input, existing?) when is_map(input) do
    # A new section may name its own id (client-chosen, so a replayed draft is deterministic).
    {input, client_id?} = client_id(input, "section_id", "dash_section_", existing?)

    keys =
      ~w(title description collapsed_by_default) ++ if(existing?, do: ["section_id"], else: [])

    client_id? and exact?(input, keys) and (not existing? or id?(input["section_id"])) and
      text?(input["title"], 512) and String.trim(input["title"]) != "" and
      text?(input["description"], 4096) and is_boolean(input["collapsed_by_default"])
  end

  defp section?(_, _), do: false

  defp widget?(input, existing?) when is_map(input) do
    {input, client_id?} = client_id(input, "placement_id", "dash_widget_", existing?)
    keys = ~w(fields observables) ++ if(existing?, do: ["placement_id"], else: [])

    client_id? and exact?(input, keys) and (not existing? or id?(input["placement_id"])) and
      widget_fields?(input["fields"]) and observables?(input["observables"])
  end

  defp widget?(_, _), do: false

  @doc "A client-chosen id for a new section or widget: `prefix` plus 1-64 of [A-Za-z0-9_-]."
  def client_id?(id, prefix) when is_binary(id) do
    String.starts_with?(id, prefix) and
      Regex.match?(~r/\A[A-Za-z0-9_-]{1,64}\z/, String.replace_prefix(id, prefix, ""))
  end

  def client_id?(_id, _prefix), do: false

  # On an add, an optional client id is checked and set aside; an update names its own id.
  defp client_id(input, key, prefix, false = _existing?) when is_map_key(input, key),
    do: {Map.delete(input, key), client_id?(input[key], prefix)}

  defp client_id(input, _key, _prefix, _existing?), do: {input, true}

  defp observables?(values) when is_list(values),
    do: length(values) <= 24 and Enum.all?(values, &id?/1) and unique?(values)

  defp observables?(_), do: false

  defp layout?(layout) when is_map(layout) do
    exact?(layout, ~w(placement_id x y w h)) and id?(layout["placement_id"]) and
      integer?(layout["x"], 0, 47) and integer?(layout["y"], 0, 100_000) and
      integer?(layout["w"], 1, 48) and integer?(layout["h"], 1, 1024)
  end

  defp layout?(_), do: false
  defp integer?(value, min, max), do: is_integer(value) and value >= min and value <= max

  defp integer_text?(value),
    do: byte_size(value) <= 5 and Regex.match?(~r/^(0|[1-9][0-9]*)$/, value)

  defp exact?(map, keys),
    do: map_size(map) == length(keys) and Enum.all?(keys, &Map.has_key?(map, &1))

  defp unique?(values), do: length(Enum.uniq(values)) == length(values)
end
