defmodule Cadence.Management.Commanding.AuthoringCatalog do
  @moduledoc "Finite target and command discovery for human request authoring."
  alias Cadence.Catalog.Command.WireEncoding
  alias Cadence.{Ids, SourceEndpoints}

  @keys ~w(command target command_after target_after command_query target_query)

  def query(params) when is_map(params) and map_size(params) <= 6 do
    if Enum.all?(params, fn {key, value} -> key in @keys and text?(value) end) do
      query = Map.new(@keys, &{&1, Map.get(params, &1, "")})

      if valid_selection?(query), do: {:ok, query}, else: {:error, :invalid_authoring_query}
    else
      {:error, :invalid_authoring_query}
    end
  end

  def query(_), do: {:error, :invalid_authoring_query}

  defp valid_selection?(query) do
    Enum.all?(~w(command target command_after target_after), fn key ->
      query[key] == "" or Ids.valid_identifier?(query[key])
    end)
  end

  def page(scope, mission, snapshot, query) do
    targets =
      SourceEndpoints.command_targets_page(
        scope.organization_id,
        mission.mission_id,
        query["target_after"],
        query["target_query"]
      )

    definitions = snapshot.catalog.runtime_definitions

    commands =
      definitions
      |> Enum.filter(fn definition ->
        definition.command_id > query["command_after"] and
          matches?(definition, query["command_query"])
      end)
      |> Enum.sort_by(& &1.command_id)
      |> Enum.take(26)

    entries = Enum.take(commands, 25)
    selected = Enum.find(definitions, &(&1.command_id == query["command"]))

    model = %{
      "version" => 2,
      "context" => %{"organizationId" => scope.organization_id, "missionId" => mission.mission_id},
      "actor_id" => scope.user.user_id,
      "mission_name" => mission.display_name,
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => query,
      "basis" => %{
        "token" => snapshot.token,
        "activation_id" => snapshot.activation_id,
        "generation" => snapshot.generation,
        "revision_id" => snapshot.basis.mission_model_revision_id,
        "plan_id" => snapshot.catalog.plan_id
      },
      "targets" => %{
        "limit" => 25,
        "entries" => Enum.map(targets.entries, &target/1),
        "next_after" => targets.next_after
      },
      "commands" => %{
        "limit" => 25,
        "entries" => Enum.map(entries, &command_reference/1),
        "next_after" => if(length(commands) > 25, do: List.last(entries).command_id, else: nil)
      },
      "selected_target" =>
        selected_target(scope.organization_id, mission.mission_id, query["target"]),
      "selected_command" => selected_command(selected, snapshot.catalog)
    }

    case Jason.encode(model) do
      {:ok, json} when byte_size(json) <= 131_072 -> {:ok, model}
      _ -> {:error, :command_authoring_catalog_too_large}
    end
  end

  def target(%{source_endpoint_id: id} = endpoint),
    do: %{
      "id" => id,
      "name" => endpoint.display_name,
      "spacecraft_id" => endpoint.spacecraft_id,
      "source_ref" => endpoint.source_ref,
      "scid" => endpoint.scid
    }

  def target(endpoint), do: Map.new(endpoint, fn {key, value} -> {Atom.to_string(key), value} end)

  defp selected_target(_, _, ""), do: nil

  defp selected_target(org, mission, id) do
    case SourceEndpoints.fetch_command_authoring_target(org, mission, id) do
      {:ok, endpoint} -> target(endpoint)
      _ -> nil
    end
  end

  defp selected_command(nil, _), do: nil

  defp selected_command(definition, catalog) do
    case Enum.find(catalog.operational_bindings, &(&1.command_id == definition.command_id)) do
      nil ->
        nil

      binding ->
        Map.merge(command_reference(definition), %{
          "description" => definition.description,
          "critical" => binding.critical,
          "hazardous" => binding.hazardous,
          "significance" =>
            if(binding.significance, do: to_string(binding.significance), else: nil),
          "supported" =>
            length(definition.argument_specs) <= 64 and WireEncoding.definition(definition) == :ok,
          "arguments" => Enum.map(Enum.take(definition.argument_specs, 64), &argument/1)
        })
    end
  end

  defp command_reference(definition),
    do: %{
      "id" => definition.command_id,
      "name" => definition.name,
      "display_name" => definition.display_name
    }

  defp argument(spec),
    do: %{
      "id" => spec.argument_id,
      "name" => spec.name,
      "description" => spec.description,
      "type" => to_string(spec.base_type),
      "required" => spec.required,
      "default_value_json" =>
        if(is_nil(spec.default_value), do: nil, else: Jason.encode!(spec.default_value)),
      "fixed_value_json" =>
        if(is_nil(spec.fixed_value), do: nil, else: Jason.encode!(spec.fixed_value)),
      "hazardous_values_json" => Jason.encode!(spec.hazardous_values)
    }

  defp matches?(definition, query) do
    query = String.downcase(String.trim(query))

    Enum.any?(
      [definition.command_id, definition.name, definition.display_name || ""],
      &String.contains?(String.downcase(&1), query)
    )
  end

  defp text?(value),
    do:
      is_binary(value) and byte_size(value) <= 240 and String.valid?(value) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
