defmodule Cadence.Reads.Dashboards.Workspace do
  @moduledoc """
  Authorized dashboard workspace read boundary.

  Runtime context and resolution dependencies are server-owned inputs, not
  browser parameters. The host must separately admit URL/interaction inputs.
  Published views never fall back to drafts; edit reads require author authority.
  """
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Documents,
    Resolution,
    ResolutionContext,
    RuntimeComposition
  }

  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.WorkspaceSnapshot

  def load(scope, mission, dashboard, mode \\ :view, opts \\ [])

  def load(
        %Scope{organization_id: org} = scope,
        mission,
        dashboard,
        mode,
        opts
      )
      when mode in [:view, :edit] and is_list(opts) do
    with {:ok, author} <- authorize(scope, mission, dashboard, mode),
         {:ok,
          %Document{organization_id: ^org, mission_id: ^mission, dashboard_id: ^dashboard} =
            document} <-
           Documents.fetch_for_mode(org, mission, dashboard, mode) do
      resolve(document, mode, author, opts)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _, _), do: {:error, :unavailable}

  @doc """
  Resolves a server-owned unsaved document through the production engine.
  Callers must retain their staging revision separately from the durable version.
  This is not an admission path for browser-supplied document maps.
  """
  def preview(scope, %Document{} = document, opts \\ []) do
    with {:ok, author} <- authorize(scope, document.mission_id, document.dashboard_id, :edit),
         true <- document.organization_id == scope.organization_id,
         true <- length(document.sections) <= 64 and length(document.placements) <= 1024 do
      resolve(document, :edit, author, opts)
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp resolve(document, mode, author, opts) do
    runtime = Keyword.get(opts, :runtime, %{})

    request =
      DashboardResolveRequest.new(%{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        document_mode: if(mode == :view, do: :published, else: :draft),
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

    {hydrated, result} = Resolution.resolve_with_document(request, context)
    WorkspaceSnapshot.build(hydrated, result, request, author)
  end

  @doc "An authorized published-view reference, without resolving widgets or reading sources."
  def reference(%Scope{organization_id: org} = scope, mission, dashboard) do
    with {:ok, _author} <- authorize(scope, mission, dashboard, :view),
         true <- mission not in [".", ".."] and dashboard not in [".", ".."],
         {:ok,
          %Document{
            organization_id: ^org,
            mission_id: ^mission,
            dashboard_id: ^dashboard,
            name: name
          }} <- Documents.fetch_for_mode(org, mission, dashboard, :view),
         true <- is_binary(name) and byte_size(name) in 1..512 and String.valid?(name) do
      {:ok, %{id: dashboard, name: name}}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def reference(_, _, _), do: {:error, :unavailable}

  @doc "Identifies an authorized unpublished dashboard without exposing draft content."
  def publication_requirement(%Scope{organization_id: org} = scope, mission, dashboard) do
    with {:ok, author} <- authorize(scope, mission, dashboard, :view),
         {:error, :dashboard_not_published} <-
           Documents.fetch_for_mode(org, mission, dashboard, :view) do
      {:ok,
       %{
         state: "publication_required",
         version: 1,
         organization_id: org,
         mission_id: mission,
         dashboard_id: dashboard,
         author: author
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def publication_requirement(_, _, _), do: {:error, :unavailable}

  defp authorize(scope, mission, dashboard, mode) do
    resource = %{organization_id: scope.organization_id, mission_id: mission}

    with true <- valid_scope?(scope, mission, dashboard),
         :ok <- Policy.authorize(scope, :operate_mission, resource),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission),
         author = Policy.authorize(scope, :author_dashboards, resource) == :ok,
         true <- mode == :view or author do
      {:ok, author}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp valid_scope?(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission, dashboard) do
    Enum.all?([scope.organization_id, user, mission, dashboard], &valid_id?/1) and
      scope.mission_id in [nil, mission]
  end

  defp valid_scope?(_, _, _), do: false

  defp valid_id?(value) when is_binary(value) and byte_size(value) in 1..256,
    do: String.valid?(value)

  defp valid_id?(_), do: false
end
