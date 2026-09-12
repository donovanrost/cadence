defmodule Cadence.Reads.Dashboards.ExecutionDiagnostics do
  @moduledoc """
  Mission-authorized published-dashboard inspection and recorded runtime decisions.

  Inspection runs the ordinary resolver at read time; it is not historical viewer
  evidence. Runtime dependencies are server-owned, never browser-supplied options.
  Recorded decisions are read independently so inspection failure cannot erase them.
  """
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Diagnostics,
    Document,
    Documents,
    Resolution,
    ResolutionContext,
    RuntimeComposition
  }

  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.ExecutionEvidence
  alias Cadence.Telemetry.RuntimeHealth

  @dto_version 2
  def dto_version, do: @dto_version

  @doc "Reauthorizes the published resource without resolving any sources or loading evidence."
  def current_version(scope, mission, dashboard) do
    with {:ok, document} <- authorized_document(scope, mission, dashboard) do
      {:ok, Document.version(document)}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(scope, mission, dashboard, opts \\ [])

  def load(%Scope{organization_id: org} = scope, mission, dashboard, opts) when is_list(opts) do
    case authorized_document(scope, mission, dashboard) do
      {:ok, document} ->
        model = %{
          version: @dto_version,
          organization_id: org,
          mission_id: mission,
          dashboard_id: dashboard,
          name: document.name,
          document_version: Document.version(document),
          loaded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          collections: inspection(document, opts) ++ decisions(org, mission, dashboard, opts)
        }

        if byte_size(Jason.encode!(model)) <= 1_048_576,
          do: {:ok, model},
          else: {:error, :unavailable}

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _), do: {:error, :unavailable}

  defp authorized_document(%Scope{organization_id: org} = scope, mission, dashboard) do
    with :ok <- authorize(scope, mission, dashboard),
         {:ok,
          %Document{organization_id: ^org, mission_id: ^mission, dashboard_id: ^dashboard} =
            document} <- Documents.fetch_for_mode(org, mission, dashboard, :view),
         true <- length(document.placements) <= 1024 and length(document.sections) <= 64 do
      {:ok, document}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp authorized_document(_, _, _), do: {:error, :unavailable}

  defp authorize(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission, dashboard) do
    resource = %{organization_id: scope.organization_id, mission_id: mission}

    with true <- Enum.all?([scope.organization_id, user, mission, dashboard], &valid_id?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <- Policy.authorize(scope, :operate_mission, resource),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      :ok
    else
      _ -> {:error, :unavailable}
    end
  end

  defp authorize(_, _, _), do: {:error, :unavailable}

  defp inspection(document, opts) do
    runtime = Keyword.get(opts, :runtime, %{})

    request =
      DashboardResolveRequest.new(%{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        document_mode: :published,
        resolve_mode: :initial,
        time_context: Map.get(runtime, :time_context, %{}),
        scope_context: Map.get(runtime, :scope_context, %{}),
        data_context: Map.get(runtime, :data_context, %{}),
        limit_context: Map.get(runtime, :limit_context, %{})
      })

    context =
      Keyword.get_lazy(opts, :resolution_context, fn ->
        RuntimeComposition.from_application()
        |> ResolutionContext.from_composition!(validate_dashboard_contract?: true)
      end)

    request |> Resolution.resolve(context) |> ExecutionEvidence.inspection()
  rescue
    _ -> ExecutionEvidence.unavailable_inspection()
  catch
    _, _ -> ExecutionEvidence.unavailable_inspection()
  end

  defp decisions(org, mission, dashboard, opts) do
    filters = [organization_id: org, mission_id: mission, dashboard_id: dashboard, limit: 51]

    {rows, source} =
      case Diagnostics.durable_runtime_invalidation_decisions(filters) do
        [] ->
          rows =
            opts
            |> Keyword.get(:runtime_health, RuntimeHealth)
            |> RuntimeHealth.snapshot()
            |> Diagnostics.runtime_invalidation_decisions(filters)

          {rows, "process_local"}

        rows ->
          {rows, "durable"}
      end

    # Scope every projection row as defense in depth, including local fallback.
    rows =
      Enum.filter(
        rows,
        &(&1.organization_id == org and &1.mission_id == mission and &1.dashboard_id == dashboard)
      )

    ExecutionEvidence.decisions(rows, source)
  rescue
    _ -> ExecutionEvidence.unavailable_decisions()
  catch
    _, _ -> ExecutionEvidence.unavailable_decisions()
  end

  defp valid_id?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: String.valid?(value)

  defp valid_id?(_), do: false
end
