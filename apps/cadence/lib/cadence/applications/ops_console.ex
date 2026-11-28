defmodule Cadence.Applications.OpsConsole do
  @moduledoc "The first-party contribution boundary for the federated Ops Console."

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  @identity %{
    application_key: "ops_console",
    application_version: 1,
    package_id: "cadence.ops_console",
    package_version: 1,
    surface_version: 1,
    release_id: "ops-console-v1",
    remote_name: "cadence_ops_console",
    manifest_path: "/assets/application-host/ops-console/mf-manifest.json",
    exposed_module: "./Application"
  }

  @surface_specs [
    %{
      id: "workspace",
      purpose: :overview,
      placement: :application_workspace,
      label: "Ops Console",
      order: 10,
      query_id: "cadence.ops.workspace",
      path: "/missions/:mission_id/ops",
      actions: []
    },
    %{
      id: "telemetry_explore",
      purpose: :operations,
      label: "Telemetry Explore",
      path: "/missions/:mission_id/ops/explore",
      actions: ["apply_filters", "apply_question"]
    },
    %{
      id: "data_sources",
      purpose: :configuration,
      label: "Data Sources",
      path: "/missions/:mission_id/ops/data-sources",
      actions: [
        "register-source",
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ]
    },
    %{
      id: "data_source_registration",
      purpose: :configuration,
      label: "Register Data Source",
      path: "/missions/:mission_id/ops/data-sources/registration/new",
      query_params: [],
      actions: ["register-source"]
    },
    %{
      id: "data_source_settings",
      purpose: :configuration,
      label: "Data Source Settings",
      path: "/missions/:mission_id/ops/data-sources/:data_source_id/settings",
      subject_param: "data_source_id",
      query_params: ["data_source_id"],
      actions: [
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ]
    },
    %{
      id: "alarms",
      purpose: :operations,
      label: "Alarms",
      path: "/missions/:mission_id/ops/alarms",
      actions: ~w(filter reset_filters)
    },
    %{
      id: "timeline",
      purpose: :activity,
      label: "Timeline",
      path: "/missions/:mission_id/ops/timeline",
      actions: ~w(apply_timeline_filters clear_timeline_selection)
    }
  ]

  @ops_actions @surface_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

  # Exact complement of the composed provider bindings. Empty entries are
  # intentional: every declared surface participates in the partition.
  @residual_action_ledger %{
    "workspace" => [],
    "telemetry_explore" => [],
    "data_sources" => [],
    "data_source_registration" => [],
    "data_source_settings" => [],
    "alarms" => [],
    "timeline" => []
  }

  @deep_route_interaction_ledger %{
    "data_source_registration" => %{
      host_actions: ["register-source"],
      navigation: ["open_data_sources"],
      phoenix_events: []
    },
    "data_source_settings" => %{
      host_actions: [
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ],
      navigation: ["open_data_sources", "open_data_source_settings"],
      phoenix_events: []
    }
  }

  @spec identity() :: map()
  def identity, do: @identity

  @spec surface_ids() :: [binary()]
  def surface_ids, do: Enum.map(@surface_specs, & &1.id)

  def surface_specs, do: @surface_specs

  @spec action_ids() :: [binary()]
  def action_ids, do: @ops_actions

  @spec surface_action_pairs() :: [{binary(), binary()}]
  def surface_action_pairs do
    Enum.flat_map(@surface_specs, fn spec -> Enum.map(spec.actions, &{spec.id, &1}) end)
  end

  @spec residual_action_ledger() :: %{binary() => [binary()]}
  def residual_action_ledger, do: @residual_action_ledger

  @spec deep_route_interaction_ledger() :: %{binary() => map()}
  def deep_route_interaction_ledger, do: @deep_route_interaction_ledger

  @spec surface_query_contract(binary()) ::
          {:ok, %{subject_param: binary() | nil, query_params: [binary()]}} | :error
  def surface_query_contract(surface_id) when is_binary(surface_id) do
    case Enum.find(@surface_specs, &(&1.id == surface_id)) do
      nil ->
        :error

      spec ->
        {:ok,
         %{
           subject_param: Map.get(spec, :subject_param),
           query_params: Map.get(spec, :query_params, [])
         }}
    end
  end

  @spec route_action_completion() :: {:complete, 0} | {:residual, non_neg_integer()}
  def route_action_completion do
    residual_count =
      @residual_action_ledger
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> length()

    if residual_count == 0, do: {:complete, 0}, else: {:residual, residual_count}
  end

  @spec application_key() :: binary()
  def application_key, do: @identity.application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.OpsConsole.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    Enum.map(@surface_specs, fn spec ->
      %SurfaceQueryContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        query_id: Map.get(spec, :query_id, "cadence.ops.#{spec.id}"),
        query_version: @identity.surface_version,
        provider: Cadence.Reads.ApplicationSurfaces.OpsConsole
      }
    end)
  end

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        surface_id: spec.id,
        surface_version: @identity.surface_version,
        federation: :module_federation,
        release_id: @identity.release_id,
        remote_name: @identity.remote_name,
        manifest_path: @identity.manifest_path,
        exposed_module: @identity.exposed_module
      }
    end)
  end

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @identity.package_id,
        package_version: @identity.package_version
      }
    ]
  end

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Ops Console",
      description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
      trust: :first_party,
      installation_policy: :platform,
      availability: :available,
      installable_scopes: [:mission],
      settings_sections: [],
      actions: action_definitions(),
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  defp surface_definition(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: @identity.surface_version,
      purpose: spec.purpose,
      scope: :mission,
      placement: Map.get(spec, :placement, :ops_workspace),
      navigation: %{label: spec.label, order: Map.get(spec, :order, 10), fallback_path: spec.path},
      subject_contract: subject_contract(spec),
      data_contract: %{
        query_id: Map.get(spec, :query_id, "cadence.ops.#{spec.id}"),
        version: @identity.surface_version
      },
      actions: spec.actions,
      refresh: if(spec.id == "workspace", do: :static, else: :after_action),
      renderer: {:trusted, "cadence.ops.console"}
    }
  end

  defp subject_contract(%{subject_param: subject_param} = spec) when is_binary(subject_param) do
    %{schema_id: "cadence.ops_console.#{spec.id}.subject", version: 1}
  end

  defp subject_contract(_spec), do: nil

  defp action_definitions do
    Enum.map(@ops_actions, fn action_id ->
      %ActionDefinition{
        action_id: action_id,
        version: @identity.application_version,
        intent: :operation,
        scope: :mission,
        input_contract: %{schema_id: "cadence.ops_console.#{action_id}.input", version: 1},
        result_contract: %{schema_id: "cadence.ops_console.#{action_id}.result", version: 1},
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        concurrency: %{strategy: :expected_version}
      }
    end)
  end
end
