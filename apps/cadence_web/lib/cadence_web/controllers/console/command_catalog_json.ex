defmodule CadenceWeb.Console.CommandCatalogJSON do
  @moduledoc """
  Wire shape of the console command catalog. Contract: docs/apogee/api/commanding.md.

  Argument values (defaults, fixed and hazardous values, choice values, range
  bounds) are JSON-encoded strings (`*_json`), because command arguments can
  be 64-bit integers that a JavaScript number can't hold exactly.
  """

  @spec list(map() | :not_active) :: map()
  def list(:not_active) do
    %{data: Map.merge(not_active(), %{commands: []}), meta: %{next_cursor: nil}}
  end

  def list(page) do
    %{
      data: Map.merge(basis(page), %{commands: Enum.map(page.commands, &entry/1)}),
      meta: %{next_cursor: page.next_after}
    }
  end

  @spec show(map() | :not_active) :: map()
  def show(:not_active), do: %{data: Map.merge(not_active(), %{command: nil})}

  def show(%{command: command} = result) do
    %{data: Map.merge(basis(result), %{command: detail(command)})}
  end

  defp not_active,
    do: %{
      state: "not_active",
      revision_id: nil,
      catalog_revision: nil,
      plan_id: nil,
      activation_id: nil
    }

  defp basis(result) do
    %{
      state: "active",
      revision_id: result.revision_id,
      catalog_revision: result.catalog_revision,
      plan_id: result.plan_id,
      activation_id: result.activation_id
    }
  end

  defp entry(command) do
    %{
      id: command.id,
      name: command.name,
      display_name: command.display_name,
      description: command.description,
      subsystem: command.subsystem,
      group: command.group,
      significance: atom_string(command.significance),
      critical: command.critical,
      hazardous: command.hazardous,
      second_go_required: command.second_go_required,
      argument_count: command.argument_count
    }
  end

  defp detail(command) do
    command
    |> entry()
    |> Map.merge(%{
      opcode_json: json_or_nil(command.opcode),
      apid: command.apid,
      service_type: command.service_type,
      service_subtype: command.service_subtype,
      release_policy_hint: command.release_policy_hint,
      arguments: Enum.map(command.arguments, &argument/1),
      verifiers: Enum.map(command.verifiers, &verifier/1),
      constraints: Enum.map(command.constraints, &constraint/1)
    })
  end

  defp argument(argument) do
    %{
      id: argument.id,
      name: argument.name,
      description: argument.description,
      type: atom_string(argument.type),
      required: argument.required,
      default_value_json: json_or_nil(argument.default_value),
      fixed_value_json: json_or_nil(argument.fixed_value),
      hazardous_values_json: Enum.map(argument.hazardous_values, &Jason.encode!/1),
      choices:
        Enum.map(argument.choices, &%{label: &1.label, value_json: Jason.encode!(&1.value)}),
      valid_range: range(argument.valid_range),
      unit: argument.unit
    }
  end

  defp range(nil), do: nil

  defp range(range),
    do: %{minimum_json: json_or_nil(range.minimum), maximum_json: json_or_nil(range.maximum)}

  defp verifier(verifier) do
    %{
      id: verifier.id,
      name: verifier.name,
      description: verifier.description,
      phase: atom_string(verifier.phase),
      timeout_ms: verifier.timeout_ms,
      delay_ms: verifier.delay_ms,
      severity: atom_string(verifier.severity)
    }
  end

  defp constraint(constraint) do
    %{
      id: constraint.id,
      name: constraint.name,
      description: constraint.description,
      type: atom_string(constraint.type),
      blocking: constraint.blocking,
      timeout_ms: constraint.timeout_ms
    }
  end

  defp json_or_nil(nil), do: nil
  defp json_or_nil(value), do: Jason.encode!(value)

  defp atom_string(nil), do: nil
  defp atom_string(value), do: to_string(value)
end
