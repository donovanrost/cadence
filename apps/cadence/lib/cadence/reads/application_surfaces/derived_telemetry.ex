defmodule Cadence.Reads.ApplicationSurfaces.DerivedTelemetry do
  @moduledoc "Scoped definition editing, immutable history and latest-value evidence."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider
  alias Cadence.Applications.{ApplicationInstallations, HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Governance
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.DerivedTelemetry.Pages
  alias Cadence.Reads.DerivedTelemetry, as: Values
  alias Cadence.SpacecraftStore

  @impl true
  def application_key, do: "derived_telemetry"
  @impl true
  def load(%Scope{} = scope, %HostContext{placement: :mission} = host, %SurfaceQueryRequest{
        application_key: "derived_telemetry",
        application_version: 1,
        surface_id: "manage",
        surface_version: 1,
        query_id: "cadence.derived_telemetry.manage",
        query_version: 1,
        params: params
      }) do
    with {:ok, query} <- Pages.parse(params),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, host.mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: host.mission_id
           }),
         {:ok, actor} <- actor(scope),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(scope, host, "derived_telemetry"),
         {:ok, options, spacecraft_name} <-
           spacecraft(scope.organization_id, host.mission_id, query["spacecraft"]) do
      base = "/missions/#{host.mission_id}/applications/derived_telemetry/manage"

      definitions =
        Governance.derived_definitions_page(scope.organization_id, host.mission_id,
          page: query["page"],
          search: query["q"]
        )

      selected = selection(scope.organization_id, host.mission_id, base, query)

      values =
        Values.latest_values_page(
          scope.organization_id,
          host.mission_id,
          options ++ [page: query["values_page"], search: query["values_q"]]
        )

      spacecraft_page = spacecraft_page(scope.organization_id, host.mission_id, query)

      data = %{
        "contract_version" => 1,
        "context" => %{
          "organization_id" => scope.organization_id,
          "mission_id" => host.mission_id,
          "actor_id" => actor,
          "installation_id" => installation.application_installation_id
        },
        "mission_name" => mission.display_name,
        "query" => query,
        "definitions" =>
          Pages.envelope(
            %{definitions | items: Enum.map(definitions.items, &summary(&1, base, query))},
            base,
            query,
            "page"
          ),
        "selection" => selected,
        "values" =>
          Pages.envelope(
            %{values | items: Enum.map(values.items, &value(&1, base, query))},
            base,
            query,
            "values_page"
          ),
        "spacecraft_filter" => spacecraft_name,
        "spacecraft" =>
          Pages.envelope(
            %{
              items:
                Enum.map(
                  spacecraft_page.items,
                  &%{"id" => &1.spacecraft_id, "label" => &1.display_name}
                ),
              page: spacecraft_page.page,
              total_count: spacecraft_page.total_count
            },
            base,
            query,
            "spacecraft_page"
          ),
        "links" => %{
          "self" => base,
          "applications" => "/missions/#{host.mission_id}/applications"
        }
      }

      {:ok,
       %{
         "data" => data,
         "navigation" => %{"fallback_href" => data["links"]["applications"], "breadcrumbs" => []}
       }}
    end
  end

  def load(_, _, _), do: {:error, :unsupported_application_surface_query}

  defp spacecraft_page(org, mission, query) do
    opts = [page: query["spacecraft_page"], page_size: 25, search: query["spacecraft_q"]]
    page = SpacecraftStore.list_spacecraft_page(org, mission, opts)
    last = max(1, ceil(page.total_count / 25))

    if page.page > last,
      do: SpacecraftStore.list_spacecraft_page(org, mission, Keyword.put(opts, :page, last)),
      else: page
  end

  defp actor(%Scope{actor_kind: :user, user: %{user_id: id}}), do: {:ok, id}

  defp actor(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}}),
    do: {:ok, id}

  defp actor(_), do: {:error, :forbidden}
  defp spacecraft(_, _, ""), do: {:ok, [], "All spacecraft and mission values"}
  defp spacecraft(_, _, "mission"), do: {:ok, [spacecraft_id: nil], "Mission values"}

  defp spacecraft(org, mission, id) do
    with {:ok, craft} <- SpacecraftStore.fetch_spacecraft(org, mission, id),
         do: {:ok, [spacecraft_id: id], craft.display_name}
  end

  defp selection(_, _, _, %{"definition" => ""}), do: nil

  defp selection(org, mission, base, query) do
    id = query["definition"]

    with {:ok, current} <- Governance.fetch_derived_definition(org, mission, id, nil),
         {:ok, inspected} <-
           Governance.fetch_derived_definition(org, mission, id, query["version"]) do
      history = Governance.derived_definition_history(org, mission, id, query["history_page"])
      sources = Pages.slice(inspected.source_point_ids, query["sources_page"])

      %{
        "available" => true,
        "id" => id,
        "current" => definition(current),
        "inspected" => definition(inspected),
        "history" =>
          Pages.envelope(
            %{history | items: Enum.map(history.items, &summary(&1, base, query))},
            base,
            query,
            "history_page"
          ),
        "sources" => Pages.envelope(sources, base, query, "sources_page")
      }
    else
      _ -> %{"available" => false, "id" => id}
    end
  end

  defp definition(d),
    do: %{
      "id" => d.derived_definition_id,
      "point_id" => d.point_id,
      "point_name" => d.point_name,
      "expression" => d.expression,
      "version" => d.version,
      "source_count" => length(d.source_point_ids)
    }

  defp summary(d, base, query),
    do: %{
      "id" => d.derived_definition_id,
      "point_id" => d.point_id,
      "point_name" => d.point_name,
      "expression_preview" => String.slice(d.expression, 0, 160),
      "version" => d.version,
      "source_count" => length(d.source_point_ids),
      "href" =>
        Pages.href(
          base,
          query
          |> Map.put("definition", d.derived_definition_id)
          |> Map.put("version", d.version)
          |> Map.put("history_page", 1)
          |> Map.put("sources_page", 1)
        )
    }

  defp value(sample, base, query),
    do: %{
      "id" => sample.derived_sample_id,
      "point_id" => sample.point_id,
      "point_name" => sample.point_name,
      "spacecraft_id" => sample.spacecraft_id,
      "definition_id" => sample.derived_definition_id,
      "definition_version" => sample.derived_definition_version,
      "trigger_sample_id" => sample.trigger_sample_id,
      "value" => inspect(sample.value, limit: 10, printable_limit: 256),
      "quality" => to_string(sample.quality_state),
      "generation_time" => datetime(sample.generation_time),
      "receipt_time" => datetime(sample.receipt_time),
      "definition_href" =>
        Pages.href(
          base,
          query
          |> Map.put("definition", sample.derived_definition_id)
          |> Map.put("version", sample.derived_definition_version)
          |> Map.put("history_page", 1)
          |> Map.put("sources_page", 1)
        )
    }

  defp datetime(nil), do: nil
  defp datetime(time), do: DateTime.to_iso8601(time)
end
