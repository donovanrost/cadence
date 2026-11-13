defmodule Cadence.Control.Activations.Description do
  @moduledoc """
  What an activation request activates, in the console's words (activations.md `<row>`):
  `kind` (`"spacecraft_configuration"` or `"telemetry_decom"`, else nil), `app` (`{key, name}` or
  nil), a `summary` sentence and the spacecraft it touches. Shared by the activation rows (L10) and
  the `activation_apply` attention items so both say the same thing.
  """

  alias Cadence.Catalog.SpacecraftModelBindings

  @decom %{key: "telemetry_decom", name: "Telemetry Decom"}

  @spec describe(map()) :: %{
          kind: binary() | nil,
          app: map() | nil,
          summary: binary(),
          spacecraft_ids: [binary()]
        }
  def describe(metadata) when is_map(metadata) do
    ids = spacecraft_ids(metadata)

    case kind(metadata) do
      "spacecraft_configuration" ->
        %{
          kind: "spacecraft_configuration",
          app: nil,
          summary: "Spacecraft configuration for #{count(ids)}",
          spacecraft_ids: ids
        }

      "telemetry_decom" ->
        %{
          kind: "telemetry_decom",
          app: @decom,
          summary: "Decom composition for #{count(ids)}",
          spacecraft_ids: ids
        }

      nil ->
        %{kind: nil, app: nil, summary: "Mission activation", spacecraft_ids: ids}
    end
  end

  def describe(_metadata), do: describe(%{})

  defp kind(%{"spacecraft_configuration_version" => _}), do: "spacecraft_configuration"
  defp kind(%{"composition" => "mission_applications"}), do: "telemetry_decom"
  defp kind(%{"application" => "telemetry_decom"}), do: "telemetry_decom"
  defp kind(_metadata), do: nil

  defp spacecraft_ids(%{"change_set" => %{"spacecraft_ids" => ids}}) when is_list(ids),
    do: Enum.sort(ids)

  defp spacecraft_ids(%{"triggering_spacecraft_id" => id}) when is_binary(id), do: [id]

  defp spacecraft_ids(metadata) do
    case SpacecraftModelBindings.reviewed_spacecraft_ids(metadata) do
      {:ok, ids} -> ids
      {:error, _not_reviewed} -> []
    end
  end

  defp count([_one]), do: "1 spacecraft"
  defp count(ids), do: "#{length(ids)} spacecraft"
end
