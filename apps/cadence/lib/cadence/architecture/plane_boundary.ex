defmodule Cadence.Architecture.PlaneBoundary do
  @moduledoc """
  Classifies plane-owned source paths and enforces ADR-015 dependency direction.

  Domain-first namespaces remain unclassified until their authority is split or
  recorded explicitly. Plane-prefixed namespaces are guarded immediately.
  """

  @plane_paths [
    management: ["lib/cadence/management.ex", "lib/cadence/management/"],
    control: ["lib/cadence/control.ex", "lib/cadence/control/"],
    data: ["lib/cadence/runtime.ex", "lib/cadence/runtime/"],
    projections: ["lib/cadence/projections.ex", "lib/cadence/projections/"],
    platform: ["lib/cadence/platform.ex", "lib/cadence/platform/"]
  ]

  @plane_file_overrides %{
    "lib/cadence/commanding/encoder.ex" => :data
  }

  @allowed_directions MapSet.new([
                        {:management, :platform},
                        {:control, :management},
                        {:control, :data},
                        {:control, :platform},
                        {:data, :platform},
                        {:projections, :management},
                        {:projections, :control},
                        {:projections, :data},
                        {:projections, :platform}
                      ])

  # Cross-plane public boundaries are deliberately explicit. Add an entry only
  # when the owning plane intends the module to be consumed across the boundary.
  @public_cross_plane_sinks MapSet.new([
                              "lib/cadence/control/activations.ex",
                              "lib/cadence/control/activations/activation_execution.ex",
                              "lib/cadence/management/activations/approved_activation.ex",
                              "lib/cadence/management/commanding/approved_command.ex",
                              "lib/cadence/platform/content_hash.ex",
                              "lib/cadence/runtime/generation_applied.ex",
                              "lib/cadence/runtime/contacts.ex",
                              "lib/cadence/runtime/commanding.ex",
                              "lib/cadence/runtime/mission_runtime_spec.ex",
                              "lib/cadence/runtime/missions.ex",
                              "lib/cadence/runtime/realized_contact_runtime_spec.ex",
                              "lib/cadence/runtime/transmit_command.ex",
                              "lib/cadence/runtime/managed_action_request.ex"
                            ])

  @type plane :: :management | :control | :data | :projections | :platform

  @type finding :: %{
          required(:kind) => :plane_direction | :plane_internal,
          required(:source) => String.t(),
          required(:sink) => String.t(),
          required(:label) => String.t(),
          required(:fingerprint) => String.t()
        }

  @spec findings_for_edge(String.t(), String.t(), term()) :: [finding()]
  def findings_for_edge(source, sink, label) do
    with source_plane when not is_nil(source_plane) <- classify(source),
         sink_plane when not is_nil(sink_plane) <- classify(sink),
         false <- source_plane == sink_plane do
      cross_plane_findings(source, source_plane, sink, sink_plane, label)
    else
      _same_or_unclassified -> []
    end
  end

  @spec classify(String.t()) :: plane() | nil
  def classify(path) when is_binary(path) do
    Map.get(@plane_file_overrides, path) ||
      Enum.find_value(@plane_paths, fn {plane, prefixes} ->
        if path_in_plane?(path, prefixes), do: plane
      end)
  end

  defp cross_plane_findings(source, source_plane, sink, sink_plane, label) do
    direction = {source_plane, sink_plane}

    cond do
      not MapSet.member?(@allowed_directions, direction) ->
        [finding(:plane_direction, source, source_plane, sink, sink_plane, label)]

      not MapSet.member?(@public_cross_plane_sinks, sink) ->
        [finding(:plane_internal, source, source_plane, sink, sink_plane, label)]

      true ->
        []
    end
  end

  defp finding(kind, source, source_plane, sink, sink_plane, label) do
    %{
      kind: kind,
      source: source,
      sink: sink,
      label: "#{label}; #{source_plane} -> #{sink_plane}",
      fingerprint: Enum.join([kind, source, sink], "|")
    }
  end

  defp path_in_plane?(path, prefixes) do
    Enum.any?(prefixes, fn prefix -> path == prefix or String.starts_with?(path, prefix) end)
  end
end
