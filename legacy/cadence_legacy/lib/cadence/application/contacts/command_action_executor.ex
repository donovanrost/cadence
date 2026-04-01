defmodule Cadence.Application.Contacts.CommandActionExecutor do
  @moduledoc """
  Executes a contact command action using the canonical commanding flow.
  """

  alias Cadence.Commands
  alias Cadence.Contacts.ContactCommandAction

  @spec execute(ContactCommandAction.t(), map()) :: {:ok, map()} | :ok | {:error, term()}
  def execute(%ContactCommandAction{} = action, context) when is_map(context) do
    command_ref = action.command_ref || %{}

    command_name = fetch_value(command_ref, :command_name)
    parameters = fetch_value(command_ref, :parameters) || %{}

    target_id =
      fetch_value(command_ref, :target_id) ||
        contact_target_id(Map.get(context, :contact))

    if is_binary(command_name) and is_binary(target_id) do
      opts = [target: target_id, user_id: Map.get(context, :actor_id)]

      case Commands.dispatch(Map.get(context, :mission_id), command_name, parameters, opts) do
        {:ok, command_log_id} ->
          {:ok, %{command_log_id: command_log_id}}

        {:error, :requires_confirmation, info} ->
          {:error, {:requires_confirmation, info}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid_command_ref}
    end
  end

  defp fetch_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp contact_target_id(nil), do: nil
  defp contact_target_id(contact), do: Map.get(contact, :spacecraft_target_id)
end
