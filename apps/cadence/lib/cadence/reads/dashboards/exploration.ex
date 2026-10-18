defmodule Cadence.Reads.Dashboards.Exploration do
  @moduledoc """
  Mission-authorized, unsaved exploration through the dashboard source resolver.

  This is a server-side read result, not a browser DTO. Frames, source diagnostics
  and metadata must pass through a dedicated projection before serialization.
  Unsupported source/scope semantics are errors, never mission-wide fallbacks.
  """
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards.{Resolution, ResolutionContext, RuntimeComposition}
  alias Cadence.Missions
  alias Cadence.Reads.Dashboards.{ExplorationQuery, ExplorationRequest, ExplorationSample}
  alias Cadence.Reads.OperationalState
  alias Cadence.SpacecraftStore

  def load(scope, mission_id, params, opts \\ [])

  def load(%Scope{} = scope, mission_id, params, opts) when is_list(opts) do
    with {:ok, %{context: query, request: request}} <- prepare(scope, mission_id, params, opts) do
      context =
        Keyword.get_lazy(opts, :resolution_context, fn ->
          RuntimeComposition.from_application()
          |> ResolutionContext.from_composition!(validate_dashboard_contract?: true)
        end)

      {_document, result} = Resolution.resolve_with_document(request, context)
      selected_sample = ExplorationSample.load(query, request, result, context)

      {:ok,
       %{query: query.query, request: request, result: result, selected_sample: selected_sample}}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _), do: {:error, :unavailable}

  @doc """
  Authorizes and compiles query intent without executing sources or inspecting samples.

  The returned server-only context preserves both the admitted navigation query
  and its effective time, scope, data, limits and bounded sampling request. It is
  not a browser DTO, saved dashboard, source-availability receipt, or reusable
  authorization grant. Consumers must reauthorize subsequent reads or authoring;
  `load/4` always prepares afresh instead of accepting a previously prepared map.
  """
  def prepare(scope, mission_id, params, opts \\ [])

  def prepare(%Scope{} = scope, mission_id, params, opts) when is_list(opts) do
    with :ok <- authorize(scope, mission_id),
         {:ok, query} <-
           ExplorationQuery.admit(params, Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)),
         :ok <- supported_source(query),
         {:ok, query} <- operational_scope(scope.organization_id, mission_id, query),
         {:ok, request} <- ExplorationRequest.build(scope.organization_id, mission_id, query) do
      {:ok, %{context: query, request: request}}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def prepare(_, _, _, _), do: {:error, :unavailable}

  defp authorize(%Scope{actor_kind: :user, user: %{user_id: user}} = scope, mission) do
    with true <- Enum.all?([scope.organization_id, mission, user], &identity?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      :ok
    else
      _ -> {:error, :unavailable}
    end
  end

  defp authorize(_, _), do: {:error, :unavailable}

  # Operational adapters need their own bounded-history/order contract before
  # accepting the same table controls. Do not silently ignore those controls.
  defp supported_source(%{logical_source: "telemetry"}), do: :ok
  defp supported_source(_), do: {:error, :unsupported_exploration_source}

  defp operational_scope(org, mission, query) do
    with :ok <- spacecraft(org, mission, query.scope.spacecraft_id),
         {:ok, primary} <- primary_scope(org, mission, query.scope.primary) do
      {:ok, %{query | scope: %{query.scope | primary: primary}}}
    end
  end

  defp primary_scope(_, _, nil), do: {:ok, nil}

  defp primary_scope(_, mission, %{kind: "mission", ids: [mission]} = primary),
    do: {:ok, primary}

  defp primary_scope(org, mission, %{kind: "spacecraft", ids: [id]} = primary) do
    with :ok <- spacecraft(org, mission, id), do: {:ok, primary}
  end

  defp primary_scope(org, mission, %{kind: "source_endpoint", ids: [id]} = primary) do
    case OperationalState.fetch_source_endpoint(org, mission, id) do
      {:ok, _} -> {:ok, primary}
      _ -> {:error, :unavailable}
    end
  end

  defp primary_scope(org, mission, %{kind: "contact", ids: [id]}) do
    with {:ok, contact} <- contact(org, mission, id),
         ids when is_list(ids) and ids != [] <- Map.get(contact, :source_endpoint_refs),
         true <- length(ids) <= 100 and Enum.all?(ids, &identity?/1),
         true <-
           Enum.all?(ids, fn endpoint ->
             match?({:ok, _}, OperationalState.fetch_source_endpoint(org, mission, endpoint))
           end) do
      # Resolve the authorized contact's endpoint set once. Retain the original
      # contact URL separately; a later missing contact must not broaden execution.
      {:ok, %{kind: "source_endpoint", mode: "many", ids: Enum.uniq(ids)}}
    else
      {:error, _} -> {:error, :unavailable}
      _ -> {:error, :unsupported_exploration_scope}
    end
  end

  defp primary_scope(_, _, %{kind: "mission"}), do: {:error, :unavailable}
  defp primary_scope(_, _, _), do: {:error, :unsupported_exploration_scope}

  defp contact(org, mission, id) do
    case OperationalState.fetch_scheduled_contact(org, mission, id) do
      {:error, :scheduled_contact_not_found} ->
        OperationalState.fetch_realized_contact(org, mission, id)

      result ->
        result
    end
  end

  defp spacecraft(_, _, nil), do: :ok

  defp spacecraft(org, mission, id) do
    case SpacecraftStore.fetch_spacecraft(org, mission, id) do
      {:ok, _} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  defp identity?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)
end
