defmodule Cadence.Commanding.Groups.Validation do
  @moduledoc """
  Validates a command-group draft without the activation lock
  (docs/apogee/domain/group-requests-q5.md): resolve each target, run the exact
  authoring validation for every (target, command) member against one
  command-catalog snapshot, evaluate the two-person policy, and compute a
  **digest** over the snapshot identity plus the validated member payloads.

  Preflight shows the digest; submit re-validates, requires the same digest,
  then re-checks the snapshot token under the lock and inserts in bulk. A
  draft is:

      %{targets: [%{spacecraft_id, source_endpoint_id: nil | id}],
        commands: [%{command_id, argument_values}],
        not_before, expires_at, priority}
  """

  alias Cadence.Commanding.{AuthoringIdentity, CommandPolicy, CommandRequest, RequestValidation}
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  @default_bounds %{max_targets: 1_000, max_commands: 16, max_members: 5_000}
  @payload_keys [
    :source_endpoint_ref,
    :command_id,
    :mission_model_revision_id,
    :argument_values,
    :resolved_argument_values,
    :significance,
    :critical,
    :hazardous,
    :release_policy_hint,
    :priority,
    :not_before,
    :expires_at
  ]

  @doc "Group size bounds (`config :cadence, :command_group_bounds`)."
  @spec bounds() :: map()
  def bounds,
    do:
      Map.merge(
        @default_bounds,
        Map.new(Application.get_env(:cadence, :command_group_bounds, []))
      )

  @spec validate(binary(), binary(), map(), map()) :: {:ok, map()} | {:error, term()}
  def validate(organization_id, mission_id, requested_by, draft) do
    with :ok <- check_size(draft) do
      Repo.transaction(fn -> in_snapshot(organization_id, mission_id, requested_by, draft) end)
    end
  end

  defp in_snapshot(organization_id, mission_id, requested_by, draft) do
    case RequestValidation.authoring_snapshot(organization_id, mission_id) do
      {:ok, snapshot} -> evaluate(organization_id, mission_id, requested_by, draft, snapshot)
      {:error, reason} -> Repo.rollback({:command_catalog_not_active, reason})
    end
  end

  @doc "Size check alone, so preflight can show the bounds without validating."
  @spec check_size(map()) :: :ok | {:error, {:command_group_too_large, map()}}
  def check_size(draft) do
    bounds = bounds()
    n = length(draft.targets)
    k = length(draft.commands)

    if n in 1..bounds.max_targets and k in 1..bounds.max_commands and n * k <= bounds.max_members,
      do: :ok,
      else: {:error, {:command_group_too_large, Map.merge(bounds, %{targets: n, commands: k})}}
  end

  defp evaluate(org, mission, requested_by, draft, snapshot) do
    now = DateTime.utc_now()
    endpoints = endpoints_by_spacecraft(org, mission)

    resolved =
      draft.targets
      |> Enum.with_index()
      |> Enum.map(fn {target, index} -> resolve_target(target, index, endpoints) end)

    {members, catalog_failures} =
      validate_members(resolved, draft, org, mission, requested_by, now, snapshot)

    commands = policy_commands(draft.commands, members, snapshot)
    policy = CommandPolicy.evaluate(commands, length(draft.targets))

    %{
      snapshot: %{
        activation_id: snapshot.activation_id,
        generation: snapshot.generation,
        token: snapshot.token
      },
      targets: Enum.map(resolved, &Map.delete(&1, :endpoint)),
      identity_failures:
        Enum.filter(resolved, & &1.failure)
        |> Enum.map(&Map.take(&1, [:index, :spacecraft_id, :failure, :failure_detail])),
      catalog_failures: catalog_failures,
      commands: commands,
      members: members,
      policy: policy,
      valid?: Enum.all?(resolved, &is_nil(&1.failure)) and catalog_failures == [],
      digest: digest(snapshot, members)
    }
  end

  defp endpoints_by_spacecraft(org, mission) do
    org
    |> SourceEndpoints.list_source_endpoints(mission)
    |> Enum.group_by(& &1.spacecraft_id)
  end

  # A target the caller already resolved to a NO-GO (Comms.UplinkResolution) keeps that reason.
  defp resolve_target(%{spacecraft_id: id, failure: failure} = target, index, _endpoints)
       when not is_nil(failure) do
    %{
      index: index,
      spacecraft_id: id,
      source_endpoint_id: nil,
      scid: nil,
      name: nil,
      endpoint: nil,
      failure: failure,
      failure_detail: Map.get(target, :failure_detail, []),
      resolution: nil
    }
  end

  defp resolve_target(%{spacecraft_id: id} = target, index, endpoints) do
    {endpoint, failure} =
      choose_endpoint(Map.get(endpoints, id, []), Map.get(target, :source_endpoint_id))

    %{
      index: index,
      spacecraft_id: id,
      source_endpoint_id: endpoint && endpoint.source_endpoint_id,
      scid: endpoint && endpoint.scid,
      name: endpoint && endpoint.display_name,
      endpoint: endpoint,
      failure: failure || missing_scid(endpoint),
      failure_detail: [],
      resolution: Map.get(target, :resolution)
    }
  end

  defp choose_endpoint(candidates, nil) do
    case candidates do
      [] -> {nil, :no_source_endpoint}
      [endpoint] -> {endpoint, nil}
      _many -> {nil, :ambiguous_source_endpoint}
    end
  end

  defp choose_endpoint(candidates, wanted),
    do:
      pick(Enum.find(candidates, &(&1.source_endpoint_id == wanted)), :source_endpoint_not_found)

  defp missing_scid(%SourceEndpoint{scid: nil}), do: :missing_scid
  defp missing_scid(_endpoint), do: nil

  defp pick(nil, failure), do: {nil, failure}
  defp pick(%SourceEndpoint{} = endpoint, _failure), do: {endpoint, nil}

  defp validate_members(resolved, draft, org, mission, requested_by, now, snapshot) do
    {members, failures} =
      for %{failure: nil} = target <- resolved,
          {command, position} <- Enum.with_index(draft.commands),
          reduce: {[], []} do
        {members, failures} ->
          request = member_request(org, mission, target, command, draft, requested_by, now)

          case RequestValidation.validate_on_snapshot(request, snapshot) do
            {:ok, enriched, state} ->
              member = %{
                target_index: target.index,
                position: position,
                request: enriched,
                target_token: state.target_token
              }

              {[member | members], failures}

            {:error, reason} ->
              failure = %{
                target_index: target.index,
                spacecraft_id: target.spacecraft_id,
                position: position,
                command_id: command.command_id,
                reason: reason
              }

              {members, [failure | failures]}
          end
      end

    {Enum.reverse(members), Enum.reverse(failures)}
  end

  defp member_request(org, mission, target, command, draft, requested_by, now) do
    CommandRequest.new(%{
      organization_id: org,
      mission_id: mission,
      source_endpoint_ref: target.source_endpoint_id,
      command_id: command.command_id,
      mission_model_revision_id: nil,
      argument_values: Map.get(command, :argument_values, %{}),
      priority: Map.get(draft, :priority, 3),
      not_before: Map.get(draft, :not_before),
      expires_at: Map.get(draft, :expires_at),
      requested_at: now,
      requested_by: requested_by
    })
  end

  # Classification per command, from a validated member when there is one, otherwise from the
  # snapshot's operational binding (so the policy holds even while some targets fail).
  defp policy_commands(commands, members, snapshot) do
    bindings = Map.new(snapshot.catalog.operational_bindings, &{&1.command_id, &1})

    commands
    |> Enum.uniq_by(& &1.command_id)
    |> Enum.map(fn %{command_id: id} ->
      source =
        Enum.find_value(members, &(&1.request.command_id == id && &1.request)) ||
          Map.get(bindings, id) || %{}

      %{
        command_id: id,
        name: Map.get(source, :command_name) || Map.get(source, :name),
        significance: Map.get(source, :significance),
        critical: Map.get(source, :critical, false),
        hazardous: Map.get(source, :hazardous, false),
        release_policy_hint: Map.get(source, :release_policy_hint)
      }
    end)
  end

  @doc "Digest of the snapshot identity and validated member payloads (ids and times excluded)."
  @spec digest(map(), [map()]) :: binary()
  def digest(snapshot, members) do
    payloads =
      Enum.map(members, fn member ->
        {member.target_index, member.position, member.target_token,
         Map.take(member.request, @payload_keys)}
      end)

    AuthoringIdentity.digest(
      {snapshot.activation_id, snapshot.generation, snapshot.token, payloads}
    )
  end
end
