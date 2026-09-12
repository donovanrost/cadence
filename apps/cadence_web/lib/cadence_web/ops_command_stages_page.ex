defmodule CadenceWeb.OpsCommandStagesPage do
  @moduledoc "Captured stage page sessions, independent reads and consumed draft write tokens."
  alias Cadence.Management.Commanding.{
    RequestAuthoring,
    StageCatalog,
    StageDrafts,
    StageItemAuthoring,
    StageSubmission
  }

  alias CadenceWeb.OpsCommandStagesActions
  alias Phoenix.Component

  @routes %{
    "/missions/:mission_id/ops/commands/stages" => "commanding.stages",
    "/missions/:mission_id/ops/commands/stages/new" => "commanding.stage-create",
    "/missions/:mission_id/ops/commands/stages/:command_stage_id" => "commanding.stage-workbench"
  }
  @catalog_keys ~w(command target command_after target_after command_query target_query)

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_command_stages_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            id: Map.fetch!(@routes, route),
            token: Ecto.UUID.generate(),
            stage_id: params["command_stage_id"],
            query: Map.drop(params, ~w(mission_id command_stage_id)),
            write_token: StageDrafts.new_write_token(),
            creation: nil,
            model: nil,
            catalog: nil,
            item_preview: nil,
            batch_preview: nil,
            operation: nil,
            notice: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_command_stages_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_command_stages_session, nil)

  def matches_read?(socket, params) when is_map(params) and map_size(params) == 3,
    do: matches?(socket, params)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = params)
      when map_size(params) == 5 and is_map(input) do
    matches?(socket, params) and
      OpsCommandStagesActions.allowed?(socket.assigns.ops_command_stages_session.id, event)
  end

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_command_stages_session] do
      %{identity: {org, user, mission, ^path}, id: ^id, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_command_stages_session)

    {page, Component.assign(socket, :ops_command_stages_session, session)}
  end

  def action(socket, event, input) do
    {result, session} =
      OpsCommandStagesActions.action(
        socket.assigns.current_scope,
        socket.assigns.ops_command_stages_session,
        event,
        input
      )

    {result, Component.assign(socket, :ops_command_stages_session, session)}
  end

  def snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    page = %{
      id: session.id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    with {:ok, fresh, mission_row} <- RequestAuthoring.authorize(scope, mission),
         {:ok, session} <- load(scope, fresh, mission_row, session) do
      session = session |> recover(scope, mission) |> renew_write() |> clear_stale_preview()
      {Map.merge(page, %{status: "ready", data: document(session)}), session}
    else
      _ -> {Map.put(page, :status, "unavailable"), session}
    end
  rescue
    _ ->
      {%{
         id: session.id,
         slot: "ops.page",
         version: 1,
         token: session.token,
         status: "unavailable"
       }, session}
  end

  defp load(scope, _, mission, %{id: "commanding.stages"} = session) do
    with {:ok, model} <- StageCatalog.directory(scope, mission.mission_id, session.query),
         do: {:ok, %{session | model: model}}
  end

  defp load(scope, fresh, mission, %{id: "commanding.stage-create"} = session) do
    with true <- map_size(session.query) == 0,
         {:ok, creation} <- creation(scope, mission.mission_id, session.creation) do
      model = %{
        "version" => 1,
        "context" => %{
          "organizationId" => fresh.organization_id,
          "missionId" => mission.mission_id
        },
        "actor_id" => fresh.user.user_id,
        "mission_name" => mission.display_name,
        "stage_id" => creation.stage_id
      }

      {:ok, %{session | creation: creation, model: model, write_token: creation.write_token}}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp load(scope, _, mission, session) do
    with {:ok, model} <-
           StageCatalog.workbench(
             scope,
             mission.mission_id,
             session.stage_id,
             Map.drop(session.query, @catalog_keys)
           ) do
      catalog =
        case RequestAuthoring.load(
               scope,
               mission.mission_id,
               Map.take(session.query, @catalog_keys)
             ) do
          {:ok, value} -> value
          _ -> nil
        end

      {:ok, %{session | model: model, catalog: catalog}}
    end
  end

  defp creation(scope, mission, nil), do: StageDrafts.prepare_create(scope, mission)
  defp creation(_, _, held), do: {:ok, held}

  defp recover(
         %{operation: %{status: "unconfirmed", event: "submit"} = operation, batch_preview: held} =
           session,
         scope,
         mission
       )
       when is_map(held) do
    case StageSubmission.recover(scope, mission, session.stage_id, held) do
      {:ok, receipt} ->
        %{session | operation: Map.merge(operation, %{status: "completed", receipt: receipt})}

      _ ->
        session
    end
  end

  defp recover(session, _, _), do: session

  defp renew_write(
         %{
           id: "commanding.stage-workbench",
           operation: %{status: status, write_token: used},
           write_token: used
         } = session
       )
       when status in ["completed", "rejected"],
       do: %{session | write_token: StageDrafts.new_write_token()}

  defp renew_write(session), do: session

  defp clear_stale_preview(%{operation: %{status: "unconfirmed"}} = session), do: session

  defp clear_stale_preview(session) do
    stage_token = get_in(session.model || %{}, ["stage", "expected_stage"])

    %{
      session
      | item_preview: valid_item_preview(session, stage_token),
        batch_preview: valid_batch_preview(session, stage_token)
    }
  end

  defp valid_item_preview(%{item_preview: item, catalog: catalog} = session, stage_token)
       when is_map(item) and is_map(catalog) do
    if item.expected_stage == stage_token and
         item.authoring.expected_basis == catalog["basis"]["token"] and
         item.authoring.target == catalog["selected_target"] and
         current_item_preview?(session, item), do: item, else: nil
  end

  defp valid_item_preview(_, _), do: nil

  defp valid_batch_preview(%{batch_preview: batch, catalog: catalog} = session, stage_token)
       when is_map(batch) and is_map(catalog) do
    if batch.expected_stage == stage_token and
         batch.batch.expected_basis == catalog["basis"]["token"] and
         current_batch_preview?(session, batch), do: batch, else: nil
  end

  defp valid_batch_preview(_, _), do: nil

  defp current_item_preview?(
         %{operation: %{status: "completed", event: "save_item", receipt: %{"item_id" => id}}},
         %{item_id: id}
       ),
       do: false

  defp current_item_preview?(session, item) do
    selected = get_in(session.model, ["selected_item"])

    if item.new?,
      do: is_nil(selected),
      else:
        is_map(selected) and selected["id"] == item.item_id and
          selected["expected_item"] == item.expected_item and selected["state"] == "draft"
  end

  defp current_batch_preview?(session, batch) do
    entries = get_in(session.model, ["items", "entries"]) || []

    Enum.all?(batch.items, fn item ->
      Enum.any?(
        entries,
        &(&1["id"] == item["id"] and &1["expected_item"] == item["expected_item"] and
            &1["state"] == "draft")
      )
    end)
  end

  defp document(%{id: "commanding.stages"} = session), do: %{directory: session.model}

  defp document(%{id: "commanding.stage-create"} = session),
    do: %{
      creation: session.model,
      write_token: available_write(session),
      operation: session.operation
    }

  defp document(session),
    do: %{
      workbench: session.model,
      catalog: session.catalog,
      write_token: available_write(session),
      operation: session.operation,
      notice: session.notice,
      item_preview:
        if(session.item_preview,
          do: StageItemAuthoring.public_preview(session.item_preview),
          else: nil
        ),
      batch_preview: public_batch(session.batch_preview)
    }

  defp public_batch(nil), do: nil

  defp public_batch(held) do
    case StageSubmission.public_preview(held) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp available_write(%{operation: %{write_token: used}, write_token: used}), do: nil
  defp available_write(session), do: session.write_token
end
