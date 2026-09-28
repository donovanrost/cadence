defmodule CadenceWeb.OpsCommandWorkspaceSession do
  @moduledoc false
  alias Cadence.Commanding.RequestValidation
  alias Cadence.Control.Commanding.WorkspaceSubmission

  alias Cadence.Management.Commanding.{
    AuthoringCatalog,
    RequestAuthoring,
    StageCatalog,
    StageDrafts,
    StageInput,
    StageSubmission,
    WorkspaceCatalog,
    WorkspaceDrafts,
    WorkspaceSettings
  }

  alias Cadence.Reads.CommandMonitor
  alias CadenceWeb.OpsCommandWorkspaceWrites, as: Writes
  @catalog_keys ~w(command target command_after target_after command_query target_query)

  def new(identity, params),
    do: %{
      identity: identity,
      token: Ecto.UUID.generate(),
      query: Map.take(params, @catalog_keys),
      monitor_query: Map.take(params, ["focus_command_id"]),
      stage_id: params["stage"],
      stage_query: %{},
      directory_query: %{},
      catalog: nil,
      workbench: nil,
      directory: nil,
      spacecraft: [],
      monitor: nil,
      creation: nil,
      write_token: StageDrafts.new_write_token(),
      operation: nil,
      write_attempt: nil,
      draft_preview: nil,
      queue_preview: nil,
      batch_preview: nil,
      create_input: nil
    }

  def load(scope, session) do
    {_, _, mission, _} = session.identity

    with {:ok, monitor} <- CommandMonitor.load(scope, mission, session.monitor_query) do
      case RequestAuthoring.authorize(scope, mission) do
        {:ok, _, _} -> load_preparation(scope, %{session | monitor: monitor})
        _ -> {:ok, %{state: "observe", monitor: monitor}, session}
      end
    end
  end

  defp load_preparation(scope, session) do
    {_, _, mission, _} = session.identity
    session = Writes.recover(scope, session)

    with {:ok, directory} <- StageCatalog.directory(scope, mission, session.directory_query),
         {:ok, workbench} <- workbench(scope, mission, session),
         {:ok, creation} <- creation(scope, mission, session.creation) do
      {catalog, spacecraft} =
        case WorkspaceCatalog.load(scope, mission, session.query) do
          {:ok, catalog, spacecraft} -> {catalog, spacecraft}
          _ -> {nil, []}
        end

      session = %{
        session
        | directory: directory,
          workbench: workbench,
          creation: creation,
          catalog: catalog,
          spacecraft: spacecraft
      }

      session = session |> renew_write() |> invalidate_previews(scope)

      with {:ok, draft} <- public_draft(session.draft_preview),
           {:ok, queue} <- public_queue(session.queue_preview),
           {:ok, batch} <- public_batch(session.batch_preview) do
        data = %{
          state: "prepare",
          initial_shelf:
            WorkspaceSettings.load(scope.organization_id, mission).effective[
              "shelf"
            ],
          directory: directory,
          catalog: catalog,
          spacecraft: spacecraft,
          workbench: workbench,
          new_stage_id: creation.stage_id,
          write_token: available_write(session),
          operation: session.operation,
          draft_preview: draft,
          queue_preview: queue,
          batch_preview: batch,
          monitor: session.monitor
        }

        {:ok, data, session}
      end
    end
  end

  def action(scope, session, "catalog_page", %{"query" => query} = input)
      when map_size(input) == 1 do
    {_, _, mission, _} = session.identity

    result =
      with {:ok, query} <- AuthoringCatalog.query(query),
           {:ok, catalog, spacecraft} <- WorkspaceCatalog.load(scope, mission, query) do
        %{status: "catalog_page", catalog: catalog, spacecraft: spacecraft}
      else
        _ -> rejected("The catalog could not be loaded. Try searching again.")
      end

    {result, session}
  end

  def action(_scope, session, "catalog_page", _input),
    do: {rejected("The catalog query is invalid."), session}

  def action(scope, session, "browse", input) do
    with {:ok, next} <- browse(session, input), {:ok, data, next} <- load(scope, next) do
      {%{status: "browsed", data: data}, next}
    else
      _ ->
        {rejected("This view is unavailable. Refresh to check your current access."), session}
    end
  end

  def action(scope, session, event, input) when event in ["preview_targets", "preview_batch"],
    do: preview(scope, session, event, input)

  def action(scope, session, event, input), do: Writes.action(scope, session, event, input)

  def available?(session),
    do: is_nil(session.operation) or session.operation.write_token != session.write_token

  def rejected(feedback), do: %{status: "rejected", feedback: feedback}

  defp browse(session, %{"kind" => "catalog", "query" => query} = input)
       when map_size(input) == 2 do
    with {:ok, query} <- AuthoringCatalog.query(query),
         do: {:ok, %{session | query: query, draft_preview: nil, queue_preview: nil}}
  end

  defp browse(session, %{"kind" => "stage", "id" => id} = input) when map_size(input) == 2 do
    if is_binary(id) and Cadence.Ids.valid_identifier?(id),
      do:
        {:ok, %{session | stage_id: id, stage_query: %{}, draft_preview: nil, batch_preview: nil}},
      else: {:error, :unavailable}
  end

  defp browse(session, %{"kind" => "items", "query" => query} = input)
       when map_size(input) == 2 do
    with {:ok, _} <- StageInput.workbench(query),
         do: {:ok, %{session | stage_query: query, batch_preview: nil}}
  end

  defp browse(session, %{"kind" => "stages", "query" => query} = input)
       when map_size(input) == 2 do
    with {:ok, _} <- StageInput.directory(query), do: {:ok, %{session | directory_query: query}}
  end

  defp browse(_, _), do: {:error, :unavailable}

  defp preview(scope, session, "preview_targets", input) do
    {_, _, mission, _} = session.identity
    session = %{session | draft_preview: nil, queue_preview: nil}

    with true <- matches_commands?(session.catalog, input["commands"]),
         {:ok, held} <- WorkspaceSubmission.preview(scope, mission, input["commands"]),
         {:ok, public} <- WorkspaceSubmission.public_preview(held) do
      draft = optional_draft(scope, mission, session, input)
      {:ok, draft_public} = public_draft(draft)

      {%{status: "previewed", preview: draft_public, queue_preview: public},
       %{session | draft_preview: draft, queue_preview: held}}
    else
      _ ->
        {rejected(
           "One or more targets or arguments could not be validated. Refresh the model and check every selected target."
         ), session}
    end
  rescue
    _ ->
      {rejected("The target previews are unavailable. Refresh and review again."),
       %{session | draft_preview: nil, queue_preview: nil}}
  end

  defp preview(scope, session, "preview_batch", input) do
    {_, _, mission, _} = session.identity
    session = %{session | batch_preview: nil}

    with true <- visible_items?(session, input["items"]),
         {:ok, held} <- StageSubmission.preview(scope, mission, session.stage_id, input),
         {:ok, public} <- StageSubmission.public_preview(held) do
      {%{status: "previewed", preview: public}, %{session | batch_preview: held}}
    else
      _ ->
        {rejected(
           "The selected drafts changed or could not be validated. Refresh and review the current items."
         ), session}
    end
  rescue
    _ ->
      {rejected("The request preview is unavailable. Refresh and review again."),
       %{session | batch_preview: nil}}
  end

  defp optional_draft(_scope, _mission, %{stage_id: nil}, _input), do: nil

  defp optional_draft(scope, mission, session, input) do
    case WorkspaceDrafts.preview(scope, mission, session.stage_id, input) do
      {:ok, draft} -> draft
      _ -> nil
    end
  end

  defp matches_commands?(catalog, commands)
       when is_map(catalog) and is_list(commands) and length(commands) in 1..25 do
    selected = catalog["selected_command"]

    is_map(selected) and selected["supported"] and
      Enum.all?(commands, fn command ->
        is_map(command) and command["command_id"] == selected["id"] and
          command["expected_basis"] == catalog["basis"]["token"]
      end)
  end

  defp matches_commands?(_, _), do: false

  def visible_items?(%{workbench: workbench}, items)
      when is_map(workbench) and is_list(items) and length(items) in 1..25 do
    Enum.all?(items, fn item ->
      is_map(item) and
        Enum.any?(
          workbench["items"]["entries"],
          &(&1["id"] == item["id"] and &1["expected_item"] == item["expected_item"] and
              &1["state"] == "draft" and &1["available"])
        )
    end)
  end

  def visible_items?(_, _), do: false

  defp workbench(_, _, %{stage_id: nil}), do: {:ok, nil}

  defp workbench(scope, mission, session),
    do: StageCatalog.workbench(scope, mission, session.stage_id, session.stage_query)

  defp creation(scope, mission, nil), do: StageDrafts.prepare_create(scope, mission)
  defp creation(_, _, held), do: {:ok, held}
  defp public_draft(nil), do: {:ok, nil}
  defp public_draft(held), do: WorkspaceDrafts.public_preview(held)
  defp public_queue(nil), do: {:ok, nil}
  defp public_queue(held), do: WorkspaceSubmission.public_preview(held)
  defp public_batch(nil), do: {:ok, nil}
  defp public_batch(held), do: StageSubmission.public_preview(held)
  defp available_write(session), do: if(available?(session), do: session.write_token, else: nil)

  defp renew_write(
         %{operation: %{status: status, write_token: used}, write_token: used} = session
       )
       when status in ["completed", "rejected"],
       do: %{session | write_token: StageDrafts.new_write_token()}

  defp renew_write(session), do: session

  defp invalidate_previews(session, scope) do
    {_, _, mission, _} = session.identity
    stage_token = get_in(session.workbench || %{}, ["stage", "expected_stage"])
    basis = get_in(session.catalog || %{}, ["basis", "token"])

    %{
      session
      | queue_preview:
          if(
            session.queue_preview &&
              Enum.all?(session.queue_preview.requests, &(&1.expected_basis == basis)) &&
              WorkspaceSubmission.current?(session.queue_preview),
            do: session.queue_preview
          ),
        draft_preview:
          if(
            current_draft?(session.draft_preview, session.stage_id, stage_token, basis) &&
              WorkspaceDrafts.current?(scope, mission, session.draft_preview),
            do: session.draft_preview
          ),
        batch_preview:
          if(current_batch?(session.batch_preview, session, stage_token, basis),
            do: session.batch_preview
          )
    }
  end

  defp current_draft?(nil, _, _, _), do: false

  defp current_draft?(draft, stage, token, basis) do
    draft.stage_id == stage and
      Enum.all?(
        draft.items,
        &(&1.expected_stage == token and &1.authoring.expected_basis == basis)
      )
  end

  defp current_batch?(nil, _, _, _), do: false

  defp current_batch?(batch, session, token, basis) do
    batch.stage_id == session.stage_id and batch.expected_stage == token and
      batch.batch.expected_basis == basis and visible_items?(session, batch.items) and
      current_targets?(batch.batch)
  end

  defp current_targets?(batch) do
    RequestValidation.with_authoring_requests(
      batch.requests,
      batch.expected_basis,
      batch.targets,
      fn _, _ -> {:ok, :current} end
    ) == {:ok, :current}
  end
end
