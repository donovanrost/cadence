defmodule Cadence.Reads.SpacecraftSwitches do
  @moduledoc """
  A spacecraft's running commanding and telemetry switches (L17/L22, fe-setup): what the active
  configuration does now, for the Setup detail read and the edit form's current value. `nil`
  when the mission has no active configuration for it.
  """

  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive

  @spec running(map(), binary()) :: %{
          commanding_enabled: boolean() | nil,
          telemetry_enabled: boolean() | nil
        }
  def running(mission, spacecraft_id) do
    entry =
      case ConfigurationActive.load(mission) do
        {:ok, %{entries: entries}} -> Map.get(entries, spacecraft_id)
        _unavailable -> nil
      end

    %{
      commanding_enabled: switch(entry, "commanding_enabled"),
      telemetry_enabled: switch(entry, "telemetry_enabled")
    }
  end

  defp switch(%{} = entry, key) do
    case Map.get(entry, key, get_in(entry, ["document", key])) do
      value when is_boolean(value) -> value
      _unknown -> nil
    end
  end

  defp switch(nil, _key), do: nil
end
