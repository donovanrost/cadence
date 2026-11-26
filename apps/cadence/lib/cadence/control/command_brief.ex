defmodule Cadence.Control.CommandBrief do
  @moduledoc """
  The request brief's context (A1, Approve): for one command request, each argument with the
  value it sets and that argument's **current value** on the request's spacecraft, plus the
  same command's prior requests to the same target.

  An argument's current value comes only from the catalog's link (domain): a command
  `state_effect` with `operation: :set` whose `argument_id` is that argument; its
  `target_ref` is the telemetry point. That point's latest value is read **for the request's
  spacecraft only** (#38: never mission-wide). Without such an effect the brief says so
  (`current: null, current_basis: "none"`); nothing is inferred from verifiers or names.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Commanding
  alias Cadence.Commanding.{ReleaseTargetGuard, RequestValidation}
  alias Cadence.Contacts
  alias Cadence.Management.Commanding.ReviewAccess
  alias Cadence.MissionModels
  alias Cadence.Telemetry.CurrentValueStore

  @prior_limit 5

  # todo(authz): Cedar should decide who may see a request's brief (today: anyone who may review
  # the mission's requests, :operate_mission since #62).
  @spec brief(Scope.t(), binary(), binary()) ::
          {:ok, map()} | {:error, :forbidden | :command_request_not_found}
  def brief(%Scope{} = scope, mission_id, command_request_id) do
    organization_id = scope.organization_id

    with {:ok, _fresh, _} <- ReviewAccess.authorize(scope, mission_id),
         {:ok, request} <-
           Commanding.fetch_command_request(organization_id, mission_id, command_request_id) do
      spacecraft_id = spacecraft_id(organization_id, mission_id, request)

      {:ok,
       %{
         command_request_id: request.command_request_id,
         command_id: request.command_id,
         spacecraft_id: spacecraft_id,
         arguments: arguments(organization_id, mission_id, request, spacecraft_id),
         prior_requests: prior(organization_id, mission_id, request)
       }}
    else
      {:error, :unavailable} -> {:error, :forbidden}
      {:error, :forbidden} -> {:error, :forbidden}
      _missing -> {:error, :command_request_not_found}
    end
  end

  defp arguments(organization_id, mission_id, request, spacecraft_id) do
    values = request.resolved_argument_values || %{}

    case RequestValidation.resolve_basis(
           organization_id,
           mission_id,
           request.mission_model_revision_id,
           request.command_id,
           request.source_endpoint_ref
         ) do
      {:ok, %{runtime_definition: definition}} ->
        describe(definition, values, fn point_id ->
          current(organization_id, mission_id, request, spacecraft_id, point_id)
        end)

      _not_active ->
        # The request's revision isn't active, so its catalog link can't be read: the values it
        # sets, with no current value (same keys as describe/3).
        Enum.map(values, fn {name, value} ->
          %{
            argument_id: nil,
            name: name,
            value_json: json(value),
            current: nil,
            current_basis: "unavailable"
          }
        end)
    end
  end

  @doc false
  # Each argument with the value it sets and, when a "set" state effect links it to a telemetry
  # point, that point's current value from `current_fun.(point_id)` (unit-testable).
  @spec describe(struct(), map(), (binary() -> map())) :: [map()]
  def describe(definition, values, current_fun) do
    Enum.map(definition.argument_specs, fn spec ->
      effect = setting_effect(definition.state_effects, spec)

      %{
        argument_id: spec.argument_id,
        name: spec.name,
        value_json: json(Map.get(values, spec.name, Map.get(values, spec.argument_id))),
        current: effect && current_fun.(effect.target_ref),
        current_basis: if(effect, do: "state_effect", else: "none")
      }
    end)
  end

  # The effect that sets this argument's telemetry point (not increments etc.).
  defp setting_effect(effects, spec) do
    Enum.find(effects || [], fn effect ->
      to_string(effect.operation) == "set" and is_binary(effect.target_ref) and
        refers_to?(effect.argument_id, spec)
    end)
  end

  defp refers_to?(ref, spec) when is_binary(ref),
    do: ref == spec.argument_id or String.ends_with?(ref, "/arguments/" <> to_string(spec.name))

  defp refers_to?(_ref, _spec), do: false

  # `point_id` is the effect's target_ref: the parameter's semantic id (current values are keyed
  # by it), shown by its qualified name.
  defp current(organization_id, mission_id, request, spacecraft_id, point_id) do
    point = point_name(organization_id, mission_id, request.mission_model_revision_id, point_id)

    sample =
      spacecraft_id &&
        CurrentValueStore.latest_value(mission_id, point_id, spacecraft_id: spacecraft_id)

    case sample do
      %{} = sample ->
        %{
          point: point,
          value_json: json(sample_value(sample)),
          at: sample.generation_time || sample.receipt_time,
          reason: nil
        }

      _none ->
        %{
          point: point,
          value_json: nil,
          at: nil,
          reason: if(spacecraft_id, do: "no_sample", else: "no_target_spacecraft")
        }
    end
  end

  # An engineering value of `false` is a value; only a missing one falls back to raw.
  defp sample_value(%{engineering_value: nil} = sample), do: sample.raw_value
  defp sample_value(sample), do: sample.engineering_value

  # (3) Through the domain's declaration read, so the storage shape stays the domain's.
  defp point_name(organization_id, mission_id, revision_id, point_id) do
    case MissionModels.declarations(organization_id, mission_id, revision_id, [point_id]) do
      {:ok, %{^point_id => %{"qualified_name" => name}}} when is_binary(name) -> name
      _none -> point_id
    end
  end

  # The request's target as release defines it (#38): its source endpoint's spacecraft.
  defp spacecraft_id(organization_id, mission_id, request) do
    case ReleaseTargetGuard.target(organization_id, mission_id, request.source_endpoint_ref) do
      {:ok, id} -> id
      _unknown -> nil
    end
  end

  defp prior(organization_id, mission_id, request) do
    target = spacecraft_id(organization_id, mission_id, request)

    organization_id
    |> Commanding.list_command_requests(mission_id,
      source_endpoint_ref: request.source_endpoint_ref
    )
    |> Enum.filter(
      &(&1.command_id == request.command_id and
          &1.command_request_id != request.command_request_id)
    )
    |> Enum.take(-@prior_limit)
    |> Enum.reverse()
    |> Enum.map(
      &%{
        command_request_id: &1.command_request_id,
        command_group_id: &1.command_group_id,
        arguments_json: json(&1.resolved_argument_values || %{}),
        state: &1.lifecycle_state,
        requested_at: &1.requested_at,
        requested_by: requester(&1.requested_by),
        reached_target: reached_target(organization_id, mission_id, target, &1)
      }
    )
  end

  # Whether the request's latest *released* attempt went over a contact serving only the target
  # (#38's check, ReleaseTargetGuard.contact/4): a request that radiated on another spacecraft
  # didn't set this one. nil: nothing released (never sent, refused, failed or uncertain).
  defp reached_target(_organization_id, _mission_id, nil, _request), do: nil

  defp reached_target(organization_id, mission_id, target, request) do
    case organization_id
         |> Commanding.list_command_release_attempts(mission_id,
           command_request_id: request.command_request_id
         )
         # Only an attempt that released sent anything: a refused or failed one (e.g. the #38
         # guard) didn't, and an uncertain one is unknown (api-ops review).
         |> Enum.filter(&(&1.lifecycle_state == :released))
         |> List.last() do
      nil ->
        nil

      attempt ->
        case Contacts.fetch_realized_contact(
               organization_id,
               mission_id,
               attempt.realized_contact_id
             ) do
          {:ok, contact} ->
            ReleaseTargetGuard.contact(organization_id, mission_id, target, contact) == :ok

          _missing ->
            false
        end
    end
  end

  defp requester(%{} = doc),
    do: %{
      kind: doc["kind"] || doc["actor_kind"],
      id: doc["id"] || doc["user_id"],
      name: doc["name"]
    }

  defp requester(_none), do: nil

  # Values travel as JSON text so 64-bit integers survive JavaScript (commanding.md).
  defp json(nil), do: nil
  defp json(value), do: Jason.encode!(value)
end
