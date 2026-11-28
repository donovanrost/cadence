defmodule Cadence.MonitoringPlanFixtures do
  @moduledoc """
  A mission's monitoring plan through the real compiler (ADR-020 P3, #451, `MonitoringLowering`):
  an imported layer with the parameters and their catalog policies, an authored layer with
  per-craft overrides, replaces and craft-only policies, compiled by `MissionModels.compile_layers/2`
  and read back by `MissionModels.fetch_runtime_plans/3`, as the runtime reads it. For the
  evaluation tests (a DataCase).

  A policy's rules are the evaluator's comparison (`above:` a threshold, `severity:` as declared),
  so the compiled entries evaluate.
  """

  alias Cadence.Catalog.MissionModel.{Declaration, Layer}
  alias Cadence.MissionModels
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SemanticObservations.{FleetAlarms, LatestAlarmStateRow}

  @doc """
  The runtime plans of a revision compiled from `catalog` (the imported policies) and `authored`
  (the mission's edits), as `%{monitoring: RuntimePlan}`.

  `catalog` is `[{name, parameter, opts}]`; `authored` is a list of `{:replace, name, opts}`,
  `{:override, target_name, name, craft_ids, opts}` or `{:craft_only, name, parameter, craft_ids, opts}`.
  `opts`: `above:`, `severity:`, `violations:`, `conformance:`, `disabled:`.
  """
  @spec compile!(binary(), binary(), [tuple()], [tuple()]) :: %{monitoring: struct()}
  def compile!(organization_id, mission_id, catalog, authored \\ []) do
    imported = imported_layer(organization_id, mission_id, catalog)

    layers = [
      imported | authored_layers(organization_id, mission_id, imported, catalog, authored)
    ]

    {:ok, result} = MissionModels.compile_layers(layers)

    {:ok, %{monitoring: monitoring}} =
      MissionModels.fetch_runtime_plans(organization_id, mission_id, result.revision.revision_id)

    %{monitoring: monitoring}
  end

  @doc """
  Makes a revision compiled from `catalog` and `authored` the mission's ACTIVE one, as an activation
  of `binding_set_id` at `version` that names it (no runtime is applied): what the reads that ask
  "which monitoring plan is active" (`Reads.MonitoredParameters`) find. Returns the runtime plans.
  """
  @spec activate!(binary(), binary(), {binary(), pos_integer()}, [tuple()], [tuple()]) ::
          %{monitoring: struct()}
  def activate!(organization_id, mission_id, {binding_set_id, version}, catalog, authored \\ []) do
    plans = compile!(organization_id, mission_id, catalog, authored)

    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        mission_id,
        binding_set_id,
        version,
        binding_set_content_sha256: "sha256:monitoring-fixture",
        publish: false,
        metadata: %{
          "mission_model" => %{"revision_id" => plans.monitoring.mission_model_revision_id}
        }
      )

    plans
  end

  @doc """
  One latest alarm state of the runtime (`semantic_latest_alarm_states`), as a transition writes it:
  `parameter` in `state` (`"warning"`, `"critical"`, `"normal"`, ...) on `spacecraft_id`, entered
  `seconds_ago` seconds ago (default 60) or at `at:`; the spacecraft's fleet summary is refreshed.
  """
  @spec alarm_state!(binary(), binary(), binary(), binary(), binary(), keyword()) :: :ok
  def alarm_state!(organization_id, mission_id, spacecraft_id, parameter, state, opts \\ []) do
    now = DateTime.utc_now()

    at =
      Keyword.get_lazy(opts, :at, fn ->
        DateTime.add(now, -Keyword.get(opts, :seconds_ago, 60), :second)
      end)

    {1, _} =
      Repo.insert_all(LatestAlarmStateRow, [
        %{
          organization_id: organization_id,
          mission_id: mission_id,
          spacecraft_scope_id: spacecraft_id,
          spacecraft_id: spacecraft_id,
          parameter_id: parameter,
          policy_id: Keyword.get(opts, :policy_id, "policy-#{parameter}"),
          evaluation_id: "eval-#{spacecraft_id}-#{parameter}",
          transition_id: "transition-#{spacecraft_id}-#{parameter}",
          effective_state: state,
          generation_time: at,
          receipt_time: at,
          state_document: JsonDocument.wrap_value(%{}),
          inserted_at: now,
          updated_at: now
        }
      ])

    :ok =
      FleetAlarms.refresh(Repo, organization_id, mission_id, [
        spacecraft_id
      ])
  end

  defp imported_layer(organization_id, mission_id, catalog) do
    # `parameter_id:` in a policy's options names its parameter's semantic id (the one a decoded
    # field's catalog point carries), so reads that map a point to its parameter find it.
    parameters =
      catalog
      |> Enum.map(fn {_name, parameter, opts} ->
        {parameter, Keyword.get(opts, :parameter_id)}
      end)
      |> Enum.uniq()
      |> Enum.map(fn
        {parameter, nil} -> %{kind: :parameter, qualified_name: parameter}
        {parameter, id} -> %{kind: :parameter, qualified_name: parameter, semantic_id: id}
      end)

    policies =
      for {name, parameter, opts} <- catalog do
        %{
          kind: :monitoring_policy,
          qualified_name: policy_name(name),
          references: [parameter_ref(parameter)],
          definition: definition(opts)
        }
      end

    Layer.new(%{
      organization_id: organization_id,
      mission_id: mission_id,
      name: "bus",
      declarations: [%{kind: :space_system, qualified_name: "/"} | parameters ++ policies]
    })
  end

  defp authored_layers(_org, _mission, _imported, _catalog, []), do: []

  defp authored_layers(organization_id, mission_id, imported, catalog, authored) do
    by_name = Map.new(imported.declarations, &{&1.qualified_name, &1})
    parameters = Map.new(catalog, fn {name, parameter, _opts} -> {name, parameter} end)

    declarations =
      Enum.map(authored, fn
        {:replace, name, opts} ->
          catalog_declaration = Map.fetch!(by_name, policy_name(name))

          %{
            kind: :monitoring_policy,
            qualified_name: policy_name(name),
            operation: :replace,
            expected_fingerprint: Declaration.fingerprint(catalog_declaration),
            references: [parameter_ref(Map.fetch!(parameters, name))],
            definition: definition(opts)
          }

        {:override, target, name, craft_ids, opts} ->
          %{
            kind: :monitoring_policy,
            qualified_name: policy_name(name),
            references: [
              parameter_ref(Map.fetch!(parameters, target)),
              %{
                expected_kind: :monitoring_policy,
                source_ref: policy_name(target),
                role: :overrides
              }
            ],
            definition: Map.put(definition(opts), "spacecraft_ids", craft_ids)
          }

        {:craft_only, name, parameter, craft_ids, opts} ->
          %{
            kind: :monitoring_policy,
            qualified_name: policy_name(name),
            references: [parameter_ref(parameter)],
            definition: Map.put(definition(opts), "spacecraft_ids", craft_ids)
          }
      end)

    [
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        layer_kind: :authored,
        name: "mission limits",
        declarations: declarations
      })
    ]
  end

  @doc "The qualified name of the monitoring policy called `name`."
  @spec policy_name(binary()) :: binary()
  def policy_name(name), do: "/monitoring/" <> name

  defp parameter_ref(parameter),
    do: %{expected_kind: :parameter, source_ref: parameter, role: :parameter}

  defp definition(opts) do
    %{
      "default_rules" => [
        %{
          "kind" => "comparison",
          "operator" => ">",
          "value" => Keyword.get(opts, :above, 10),
          "severity" => Keyword.get(opts, :severity, "critical")
        }
      ],
      "minimum_violations" => Keyword.get(opts, :violations, 1),
      "minimum_conformance" => Keyword.get(opts, :conformance, 1),
      "disabled" => Keyword.get(opts, :disabled, false)
    }
  end
end
