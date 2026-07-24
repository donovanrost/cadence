defmodule Cadence.Architecture.WebBoundary do
  @moduledoc """
  Prevents production web code from depending on historical catch-all boundary
  modules. Resource-owned API adapters may delegate during the migration; new
  controllers and LiveViews must depend on those resource adapters directly.
  """

  @legacy_prefixes [
    "lib/cadence_web/control_plane_json",
    "lib/cadence_web/control_plane_params"
  ]

  @guarded_sinks MapSet.new([
                   "lib/cadence_web/control_plane_json.ex",
                   "lib/cadence_web/control_plane_json/commanding.ex",
                   "lib/cadence_web/control_plane_json/operations.ex",
                   "lib/cadence_web/control_plane_params.ex",
                   "lib/cadence_web/control_plane_params/commanding.ex"
                 ])

  @spec findings_for_edge(String.t(), String.t(), term()) :: [map()]
  def findings_for_edge(source, sink, label) do
    if MapSet.member?(@guarded_sinks, sink) and production_caller?(source) and
         not resource_adapter?(source) do
      [
        %{
          kind: :web_catch_all,
          source: source,
          sink: sink,
          label: to_string(label),
          fingerprint: Enum.join([:web_catch_all, source, sink], "|")
        }
      ]
    else
      []
    end
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
