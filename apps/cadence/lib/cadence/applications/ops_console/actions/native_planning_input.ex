defmodule Cadence.Applications.OpsConsole.Actions.NativePlanningInput do
  @moduledoc "Declared native text and capability inputs, separate from generic application requests."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.RequirementDeclarationInput
  alias Cadence.Applications.OpsConsole.Actions.RequirementTemplateInput

  def admit(%{"contact_requirement" => form} = input) when map_size(input) == 1,
    do: form(input, form, RequirementDeclarationInput.fields())

  def admit(%{"template" => form} = input) when map_size(input) == 1,
    do: form(input, form, RequirementTemplateInput.fields())

  def admit(%{"token" => token} = input) when map_size(input) == 1 do
    if text?(token, 8_192) and token != "", do: {:ok, input}, else: {:error, :invalid_input}
  end

  def admit(%{"reason" => reason, "provider_reservation_id" => _, "change_evidence" => _} = input)
      when map_size(input) == 3,
      do: reason(input, "reason", reason)

  def admit(%{"contact_plan_id" => _, "plan_evidence" => _} = input)
      when map_size(input) == 3 do
    case Map.take(input, ~w(submission decision)) |> Map.to_list() do
      [{wrapper, %{"reason" => value} = reason}] when map_size(reason) == 1 ->
        reason(input, wrapper, value)

      _ ->
        {:error, :invalid_input}
    end
  end

  def admit(input), do: JSONBoundary.safe(input)

  defp form(input, fields, expected) when is_map(fields) do
    if Enum.sort(Map.keys(fields)) == Enum.sort(expected) and
         Enum.all?(Map.values(fields), &text?(&1, 4_096)),
       do: {:ok, input},
       else: {:error, :invalid_input}
  end

  defp form(_, _, _), do: {:error, :invalid_input}

  defp reason(input, wrapper, value) do
    with true <- text?(value, 4_096),
         {:ok, _} <- JSONBoundary.safe(Map.delete(input, wrapper)),
         do: {:ok, input},
         else: (_ -> {:error, :invalid_input})
  end

  defp text?(value, bytes),
    do: is_binary(value) and byte_size(value) <= bytes and String.valid?(value)
end
