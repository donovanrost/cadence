defmodule Cadence.Dashboards.Creation do
  @moduledoc "Scoped blank, clone and import creation independent of frontend delivery."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{Document, DocumentCodec, Documents}
  alias Cadence.Missions

  def authorize(
        %Scope{organization_id: org, mission_id: scoped, user: %{user_id: user}} = scope,
        mission
      )
      when is_binary(org) and org != "" and is_binary(mission) and mission != "" and
             is_binary(user) and user != "" and (is_nil(scoped) or scoped == mission) do
    with :ok <-
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: org,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(org, mission),
         do: :ok
  end

  def authorize(_, _), do: {:error, :forbidden}

  def create(scope, mission, model, input) do
    with :ok <- authorize(scope, mission),
         {:ok, fields} <- fields(input, model.mode),
         {:ok, document} <- document(scope, mission, model, fields) do
      case Documents.persist(scope.organization_id, document) do
        {:ok, saved} ->
          {:ok,
           %{dashboard_id: saved.dashboard_id, version: Document.version(saved), mode: model.mode}}

        _ ->
          {:error, :unknown}
      end
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  defp fields(input, mode) when is_map(input) and map_size(input) <= 3 do
    keys = if mode == "import", do: ~w(name description document_json), else: ~w(name description)

    with true <- Enum.sort(Map.keys(input)) == Enum.sort(keys),
         true <- text?(input["name"], 512) and String.trim(input["name"]) != "",
         true <- text?(input["description"], 4096),
         true <- mode != "import" or text?(input["document_json"], 262_144) do
      {:ok,
       %{
         name: String.trim(input["name"]),
         description: String.trim(input["description"]),
         json: input["document_json"]
       }}
    else
      _ -> {:invalid, :fields}
    end
  end

  defp fields(_, _), do: {:invalid, :fields}

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) <= max and String.valid?(value)

  defp document(scope, mission, %{mode: "new"}, fields) do
    {:ok,
     %Document{
       dashboard_id: Cadence.Ids.new("ops_dashboard"),
       organization_id: scope.organization_id,
       mission_id: mission,
       name: fields.name,
       description: fields.description,
       metadata: %{"source" => "dashboard_creation", "created_by" => scope.user.user_id}
     }}
  end

  defp document(scope, mission, %{mode: "clone", source: source}, fields) do
    case Documents.fetch_for_mode(scope.organization_id, mission, source.id, :edit) do
      {:ok, document} ->
        if Document.version(document) == source.version,
          do: {:ok, copy(document, scope, mission, fields, "dashboard_clone")},
          else: {:invalid, :source_changed}

      _ ->
        {:invalid, :source_changed}
    end
  end

  defp document(scope, mission, %{mode: "import"}, fields) do
    case DocumentCodec.decode_import(fields.json) do
      {:ok, document} -> {:ok, copy(document, scope, mission, fields, "dashboard_import")}
      _ -> {:invalid, :document}
    end
  end

  defp document(_, _, _, _), do: {:invalid, :fields}

  defp copy(document, scope, mission, fields, source) do
    DocumentCodec.copy_for_scope(document, scope.organization_id, mission,
      name: fields.name,
      description: fields.description,
      source: source,
      source_dashboard_id: document.dashboard_id,
      actor_id: scope.user.user_id
    )
  end
end
