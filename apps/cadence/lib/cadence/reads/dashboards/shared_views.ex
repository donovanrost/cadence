defmodule Cadence.Reads.Dashboards.SharedViews do
  @moduledoc "Authorized mission shares and immutable definition snapshots."
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    AuthoringInput,
    DashboardResolveRequest,
    Document,
    Documents,
    Management,
    Resolution,
    ResolutionContext,
    RuntimeComposition,
    SharedViewContext
  }

  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.WorkspaceSnapshot
  @max_definition_bytes 524_288

  def load(scope, mission, kind, id, opts \\ []) do
    with :ok <- authorize(scope, mission),
         true <- AuthoringInput.id?(id),
         {:ok, record, document} <- fetch(scope.organization_id, mission, kind, id),
         true <- AuthoringInput.id?(record.dashboard_id),
         true <- record.data_visibility in ~w(definition_only authorized_runtime_data),
         {:ok, runtime} <- SharedViewContext.admit(record.runtime_context, mission),
         {:ok, definition} <-
           definition(document, scope.organization_id, mission, record.dashboard_id),
         {:ok, canvas} <- canvas(document, record.data_visibility, runtime, kind, opts) do
      {:ok,
       %{
         version: 1,
         organization_id: scope.organization_id,
         mission_id: mission,
         id: id,
         kind: Atom.to_string(kind),
         dashboard_id: record.dashboard_id,
         data_visibility: record.data_visibility,
         data_semantics: semantics(kind, record),
         created_at: DateTime.to_iso8601(record.inserted_at),
         expires_at: expiration(kind, record),
         loaded_at: DateTime.to_iso8601(DateTime.utc_now()),
         runtime_context: record.runtime_context,
         definition: definition,
         canvas: canvas
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp authorize(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission) do
    with true <- Enum.all?([scope.organization_id, user, mission], &AuthoringInput.id?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission),
         do: :ok
  end

  defp authorize(_, _), do: {:error, :unavailable}

  defp fetch(org, mission, :share, id) do
    with {:ok, share} <- Management.fetch_active_share(org, mission, id),
         true <- share.access_policy == "mission_member" do
      document =
        case Documents.fetch_for_mode(org, mission, share.dashboard_id, :view) do
          {:ok, document} -> document
          _ -> nil
        end

      {:ok, share, document}
    end
  end

  defp fetch(org, mission, :snapshot, id) do
    with {:ok, snapshot} <- Management.fetch_snapshot(org, mission, id),
         true <-
           snapshot.data_semantics in ~w(definition_at_version_current_data frozen_time_window),
         document = Document.from_map(snapshot.document),
         true <- Document.version(document) == snapshot.dashboard_version,
         true <-
           snapshot.data_semantics != "frozen_time_window" or
             (is_binary(snapshot.runtime_context["from"]) and
                is_binary(snapshot.runtime_context["to"])) do
      {:ok, snapshot, document}
    end
  end

  defp fetch(_, _, _, _), do: {:error, :unavailable}

  defp definition(nil, _, _, _), do: {:ok, nil}

  defp definition(
         %Document{organization_id: org, mission_id: mission, dashboard_id: id} = doc,
         org,
         mission,
         id
       ) do
    with true <- valid_definition?(doc),
         {:ok, json} <- Jason.encode(Document.to_map(doc)),
         true <- byte_size(json) <= @max_definition_bytes do
      {:ok,
       %{
         name: doc.name,
         description: doc.description || "",
         version: Document.version(doc),
         placements: length(doc.placements),
         sections: length(doc.sections),
         json: json
       }}
    end
  end

  defp definition(_, _, _, _), do: {:error, :unavailable}

  defp valid_definition?(doc) do
    is_integer(Document.version(doc)) and Document.version(doc) in 1..9_007_199_254_740_990 and
      AuthoringInput.text?(doc.name, 4096) and doc.name != "" and
      AuthoringInput.text?(doc.description || "", 16_384) and
      length(doc.placements) <= 1024 and length(doc.sections) <= 64
  end

  defp canvas(nil, _, _, _, _), do: {:ok, nil}
  # No runtime composition, hydration, planning, source execution or frames for definition-only.
  defp canvas(_, "definition_only", _, _, _), do: {:ok, nil}

  defp canvas(doc, "authorized_runtime_data", runtime, kind, opts) do
    request =
      DashboardResolveRequest.new(
        Map.merge(runtime, %{
          organization_id: doc.organization_id,
          mission_id: doc.mission_id,
          dashboard_id: doc.dashboard_id,
          document: doc,
          document_mode: if(kind == :share, do: :published, else: :draft_preview),
          resolve_mode: :initial
        })
      )

    context =
      Keyword.get_lazy(opts, :resolution_context, fn ->
        RuntimeComposition.from_application()
        |> ResolutionContext.from_composition!(validate_dashboard_contract?: true)
      end)

    {hydrated, result} = Resolution.resolve_with_document(request, context)

    with {:ok, model} <- WorkspaceSnapshot.build(hydrated, result, request, false) do
      {:ok, %{model | document_mode: if(kind == :share, do: "published", else: "snapshot")}}
    end
  end

  defp semantics(:share, _), do: "published_definition_current_data"
  defp semantics(:snapshot, record), do: record.data_semantics
  defp expiration(:snapshot, _), do: nil
  defp expiration(:share, %{expires_at: nil}), do: nil
  defp expiration(:share, %{expires_at: at}), do: DateTime.to_iso8601(at)
end
