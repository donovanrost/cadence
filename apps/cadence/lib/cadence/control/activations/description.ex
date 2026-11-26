defmodule Cadence.Control.Activations.Description do
  @moduledoc """
  What an activation request activates, in the console's words (activations.md `<row>`):
  `kind` (`"spacecraft_configuration"` or `"telemetry_decom"`, else nil), `app` (`{key, name}` or
  nil), a `summary` sentence and the spacecraft it touches. Shared by the activation rows (L10) and
  the `activation_apply` attention items so both say the same thing.
  """

  alias Cadence.Catalog.RequestSpacecraft

  @decom %{key: "telemetry_decom", name: "Telemetry Decom"}

  @doc """
  Describes a request (anything with `:organization_id`, `:mission_id` and `:metadata`). The
  summary's count comes from the metadata's reference alone, with no query; `ids: true` also
  loads the covered spacecraft ids (`spacecraft_ids`, `[]` otherwise), for the callers that name
  them: a request's detail, a refusal, an apply's failure.
  """
  @spec describe(map(), keyword()) :: %{
          kind: binary() | nil,
          app: map() | nil,
          summary: binary(),
          spacecraft_count: non_neg_integer(),
          spacecraft_ids: [binary()]
        }
  def describe(request, opts \\ [])

  def describe(%{metadata: metadata} = request, opts) when is_map(metadata) do
    ids =
      if Keyword.get(opts, :ids, false),
        do: RequestSpacecraft.ids(request.organization_id, request.mission_id, metadata),
        else: []

    count = RequestSpacecraft.count(metadata) || length(ids)
    describe(kind(metadata), count, ids)
  end

  def describe(_request, _opts), do: describe(nil, 0, [])

  defp describe("spacecraft_configuration", count, ids),
    do: %{
      kind: "spacecraft_configuration",
      app: nil,
      summary: "Spacecraft configuration for #{noun(count)}",
      spacecraft_count: count,
      spacecraft_ids: ids
    }

  defp describe("telemetry_decom", count, ids),
    do: %{
      kind: "telemetry_decom",
      app: @decom,
      summary: "Decom composition for #{noun(count)}",
      spacecraft_count: count,
      spacecraft_ids: ids
    }

  defp describe(nil, count, ids),
    do: %{
      kind: nil,
      app: nil,
      summary: "Mission activation",
      spacecraft_count: count,
      spacecraft_ids: ids
    }

  defp kind(%{"spacecraft_configuration_version" => _}), do: "spacecraft_configuration"
  defp kind(%{"composition" => "mission_applications"}), do: "telemetry_decom"
  defp kind(%{"application" => "telemetry_decom"}), do: "telemetry_decom"
  defp kind(_metadata), do: nil

  defp noun(1), do: "1 spacecraft"
  defp noun(count), do: "#{count} spacecraft"
end
