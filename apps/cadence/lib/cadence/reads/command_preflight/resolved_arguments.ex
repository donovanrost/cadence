defmodule Cadence.Reads.CommandPreflight.ResolvedArguments do
  @moduledoc """
  U68 R1 (ux, fe-ops): where the server's argument values differ from what was entered, so Arm
  (preflight) and Approve (the group read) can show it. The server changes two things only:

    * a blank argument takes the catalog's **default** or **fixed** value (`Invocation.resolve`);
    * a float argument encoded as IEEE 754 single precision radiates the nearest 32-bit value,
      which can differ from the value resolved (`sent_value_json`).

  Rows are per stacked command (`%{position => rows}`), one per distinct difference, naming the
  targets it applies to (`spacecraft_ids`, `nil` when it applies to every target of that command).
  Each row: `name`, `entered_value_json` (`nil` = not entered), `resolved_value_json`,
  `sent_value_json` (`nil` = goes out as resolved), `unit`, `source` (`entered | default |
  fixed`, or `catalog` when the member's pinned definition can't be read to say which).
  """

  alias Cadence.Commanding.RequestValidation
  alias Cadence.Reads.CatalogDeclarations

  @type row :: %{
          name: binary(),
          entered_value_json: binary() | nil,
          resolved_value_json: binary(),
          sent_value_json: binary() | nil,
          unit: binary() | nil,
          source: binary(),
          spacecraft_ids: [binary()] | nil
        }

  @doc "Preflight: `members` are validation members (`request`, `position`, `target_index`)."
  @spec for_preflight(binary(), binary(), [map()], %{non_neg_integer() => map()}) ::
          %{non_neg_integer() => [row()]}
  def for_preflight(org, mission, members, targets_by_index) do
    members
    |> Enum.map(fn member ->
      %{
        position: member.position,
        spacecraft_id: targets_by_index |> Map.get(member.target_index, %{}) |> spacecraft_id(),
        request: member.request
      }
    end)
    |> by_position(org, mission)
  end

  @doc "The group read: `members` are the group's stored requests; rejected ones are skipped."
  @spec for_group(binary(), binary(), map(), [map()]) :: %{non_neg_integer() => [row()]}
  def for_group(org, mission, group, members) do
    spacecraft = Map.new(group.targets, &{&1["index"], &1["spacecraft_id"]})

    members
    |> Enum.reject(&(&1.lifecycle_state == :rejected))
    |> Enum.map(fn request ->
      %{
        position: request.group_slot.position,
        spacecraft_id: Map.get(spacecraft, request.group_slot.target_index),
        request: request
      }
    end)
    |> by_position(org, mission)
  end

  defp spacecraft_id(%{spacecraft_id: id}), do: id
  defp spacecraft_id(_target), do: nil

  defp by_position(members, org, mission) do
    specs = specs_by_key(org, mission, Enum.map(members, & &1.request))

    members
    |> Enum.group_by(& &1.position)
    |> Map.new(fn {position, same} ->
      everyone = same |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()
      {position, rows(same, specs, everyone)}
    end)
  end

  defp rows(members, specs, everyone) do
    members
    |> Enum.flat_map(fn member ->
      member.request
      |> differences(Map.get(specs, key(member.request)))
      |> Enum.map(&{&1, member.spacecraft_id})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {row, _ids} -> row.order end)
    |> Enum.map(fn {row, ids} ->
      ids = Enum.uniq(ids)

      row
      |> Map.delete(:order)
      |> Map.put(:spacecraft_ids, if(Enum.sort(ids) == Enum.sort(everyone), do: nil, else: ids))
    end)
  end

  @doc false
  # One member's differing rows, given its pinned `%{specs: [ArgumentSpec], units: %{id => unit}}`
  # (nil when that definition couldn't be read).
  def differences(request, definition) do
    entered = stringify(request.argument_values || %{})
    resolved = stringify(request.resolved_argument_values || %{})
    specs = if definition, do: definition.specs, else: []
    by_name = Map.new(specs, &{&1.name, &1})
    order = specs |> Enum.with_index() |> Map.new(fn {spec, i} -> {spec.name, i} end)

    resolved
    |> Enum.map(fn {name, value} ->
      spec = Map.get(by_name, name)

      %{
        order: {Map.get(order, name, length(specs)), name},
        name: name,
        entered_value_json: if(Map.has_key?(entered, name), do: json(entered[name])),
        resolved_value_json: json(value),
        sent_value_json: sent(spec, value),
        unit: unit(spec, definition),
        source: source(spec, Map.has_key?(entered, name))
      }
    end)
    |> Enum.filter(&(&1.source != "entered" or &1.sent_value_json != nil))
  end

  defp source(_spec, true), do: "entered"
  defp source(%{fixed_value: fixed}, false) when not is_nil(fixed), do: "fixed"
  defp source(%{default_value: default}, false) when not is_nil(default), do: "default"
  defp source(_spec, false), do: "catalog"

  # IEEE 754 single precision radiates the nearest 32-bit value; nil when that's the same number.
  defp sent(
         %{base_type: :float, encoding: %{float_encoding: :ieee754, size_bits: 32}},
         value
       )
       when is_number(value) do
    <<single::float-32>> = <<value::float-32>>
    if single == value, do: nil, else: json(single)
  rescue
    _unencodable -> nil
  end

  defp sent(_spec, _value), do: nil

  defp unit(nil, _definition), do: nil

  defp unit(spec, definition) do
    Map.get(definition.units, spec.argument_id) ||
      blank_to_nil(get_in(spec.metadata || %{}, ["display_unit"]))
  end

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp json(value), do: Jason.encode!(value)

  defp stringify(values), do: Map.new(values, fn {key, value} -> {to_string(key), value} end)

  defp key(request), do: {request.mission_model_revision_id, request.command_id}

  # Once per (pinned revision, command), as VerifierGroups: the same specs whatever the target.
  defp specs_by_key(org, mission, requests) do
    requests
    |> Enum.uniq_by(&key/1)
    |> Map.new(fn request -> {key(request), definition(org, mission, request)} end)
  end

  defp definition(org, mission, request) do
    case RequestValidation.resolve_basis(
           org,
           mission,
           request.mission_model_revision_id,
           request.command_id,
           request.source_endpoint_ref
         ) do
      {:ok, %{runtime_definition: %{argument_specs: specs}}} when is_list(specs) ->
        %{specs: specs, units: units(org, mission, request.mission_model_revision_id, specs)}

      _unavailable ->
        nil
    end
  end

  defp units(_org, _mission, _revision, []), do: %{}

  defp units(org, mission, revision, specs) do
    ids = Enum.map(specs, & &1.argument_id)
    declarations = CatalogDeclarations.closure(org, mission, revision, ids)
    Map.new(ids, &{&1, CatalogDeclarations.argument_facts(declarations, &1).unit})
  end
end
