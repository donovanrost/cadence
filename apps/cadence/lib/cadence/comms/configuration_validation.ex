defmodule Cadence.Comms.ConfigurationValidation do
  @moduledoc "Pure validation shared by management-owned Comms configuration stores."

  @spec mission_id(term()) :: :ok | {:error, :missing_mission_id}
  def mission_id(mission_id) when is_binary(mission_id) and mission_id != "", do: :ok
  def mission_id(_mission_id), do: {:error, :missing_mission_id}

  @spec required_binary(term(), term()) :: :ok | {:error, term()}
  def required_binary(value, _reason) when is_binary(value) and value != "", do: :ok
  def required_binary(_value, reason), do: {:error, reason}

  @spec reusable_refs([term()]) ::
          :ok | {:error, :duplicate_contact_runtime_config_reference}
  def reusable_refs(refs) when is_list(refs) do
    if length(refs) == MapSet.size(MapSet.new(refs)) do
      :ok
    else
      {:error, :duplicate_contact_runtime_config_reference}
    end
  end
end
