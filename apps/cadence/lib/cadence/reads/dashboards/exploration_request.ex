defmodule Cadence.Reads.Dashboards.ExplorationRequest do
  @moduledoc """
  Compiles admitted exploration context into an unsaved resolver document.

  The definition is an execution input, never a persisted or published dashboard.
  Callers must authorize the mission and operational scope before resolving it.
  Navigation-only selection does not change the source query or its identity.
  """
  alias Cadence.Dashboards.{DashboardResolveRequest, Document}

  def build(organization_id, mission_id, %{point_id: point} = context)
      when is_binary(point) and byte_size(point) > 0 do
    latest? = Map.get(context.query, "time_mode", "latest") == "latest"

    identity = %{
      organization_id: organization_id,
      mission_id: mission_id,
      point_id: point,
      logical_source: context.logical_source,
      time: context.time,
      data: context.data,
      scope: context.scope,
      limits: context.limits,
      limit: context.limit,
      order: context.order,
      latest: latest?
    }

    id =
      "exploration-" <>
        (:crypto.hash(:sha256, :erlang.term_to_binary(identity, [:deterministic]))
         |> Base.encode16(case: :lower))

    document =
      Document.from_map(%{
        dashboard_id: id,
        organization_id: organization_id,
        mission_id: mission_id,
        name: "Exploration",
        metadata: %{ephemeral: true},
        placements: [
          %{
            placement_id: "exploration",
            layout: %{x: 0, y: 0, w: 12, h: 4},
            content: %{
              kind: "embedded",
              widget_def: %{
                widget_type_id:
                  if(latest?, do: "cadence.value_tile", else: "cadence.time_series"),
                widget_type_version: 1,
                title: point,
                binding: %{
                  source: context.logical_source,
                  observables: [point],
                  scope_mode: "context",
                  data_mode: "context",
                  value_type: "engineering",
                  sampling: if(latest?, do: "latest", else: "raw_series"),
                  overlays: []
                },
                options: %{}
              }
            }
          }
        ]
      })

    {:ok,
     DashboardResolveRequest.new(%{
       organization_id: organization_id,
       mission_id: mission_id,
       dashboard_id: id,
       document: document,
       document_mode: :draft_preview,
       resolve_mode: :initial,
       time_context: context.time,
       scope_context: context.scope,
       data_context: context.data,
       limit_context: context.limits,
       interaction_context: %{
         source_query: %{
           max_raw_points: context.limit,
           order: if(context.order == "asc", do: :asc, else: :desc)
         }
       }
     })}
  end

  def build(_, _, _), do: {:error, :point_required}
end
