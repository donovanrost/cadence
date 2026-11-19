defmodule Cadence.Catalog.Importers.CadenceYamlDatabase.ArgumentCriteria do
  @moduledoc """
  `value_from_argument` on a verifier's criteria: compare the subject with the value the
  command was sent with (e.g. SET_MODE's `HK.sc_mode` == its `mode` argument). The name must be
  one of the command's own arguments, and only a comparison takes it, instead of `value`. The
  argument/parameter type match is checked when the model is lowered, where both types are known.
  """

  @spec validate(map() | nil, map(), binary()) :: :ok | {:error, {:validation_error, binary()}}
  def validate(nil, _command, _field), do: :ok

  def validate(criteria, command, field) when is_map(criteria) do
    with :ok <- own(criteria, command, field) do
      criteria
      |> Map.get("conditions", [])
      |> List.wrap()
      |> Enum.reduce_while(:ok, &nested(&1, &2, command, field <> ".conditions"))
    end
  end

  # Shape errors are reported by the criteria validation itself.
  def validate(_criteria, _command, _field), do: :ok

  defp nested(criteria, :ok, command, field) do
    case validate(criteria, command, field) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp own(%{"value_from_argument" => name} = criteria, command, field)
       when not is_nil(name) do
    cond do
      not is_binary(name) ->
        error(field, "value_from_argument must be an argument name")

      Map.get(criteria, "criteria_type", "comparison") != "comparison" ->
        error(field, "value_from_argument only applies to a comparison")

      Map.has_key?(criteria, "value") ->
        error(field, "can't have both value and value_from_argument")

      name not in argument_names(command) ->
        error(
          field,
          "value_from_argument names '#{name}', which isn't an argument of this command"
        )

      true ->
        :ok
    end
  end

  defp own(_criteria, _command, _field), do: :ok

  defp argument_names(command) do
    command
    |> Map.get("parameters")
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [name]
      _other -> []
    end)
  end

  defp error(field, reason), do: {:error, {:validation_error, "#{field} #{reason}"}}
end
