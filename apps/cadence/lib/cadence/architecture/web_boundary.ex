defmodule Cadence.Architecture.WebBoundary do
  @moduledoc """
  Prevents production web code from depending on historical catch-all boundary
  modules. Controllers and LiveViews must depend on resource-owned adapters;
  any reintroduced adapter dependency is reported separately as regression.
  """

  @legacy_prefixes [
    "lib/cadence_web/control_plane_json",
    "lib/cadence_web/control_plane_params"
  ]

  @spec findings_for_edge(String.t(), String.t(), term()) :: [map()]
  def findings_for_edge(source, sink, label) do
    cond do
      not legacy_boundary?(sink) or not production_caller?(source) ->
        []

      resource_adapter?(source) ->
        [finding(:web_legacy_adapter, source, sink, label)]

      true ->
        [finding(:web_catch_all, source, sink, label)]
    end
  end

  defp finding(kind, source, sink, label) do
    %{
      kind: kind,
      source: source,
      sink: sink,
      label: to_string(label),
      fingerprint: Enum.join([kind, source, sink], "|")
    }
  end

  defp production_caller?(source),
    do: String.starts_with?(source, "lib/cadence_web/") and not legacy_boundary?(source)

  defp resource_adapter?(source), do: String.starts_with?(source, "lib/cadence_web/api/")

  defp legacy_boundary?(path) do
    Enum.any?(@legacy_prefixes, fn prefix ->
      path == prefix <> ".ex" or String.starts_with?(path, prefix <> "/")
    end)
  end
end
