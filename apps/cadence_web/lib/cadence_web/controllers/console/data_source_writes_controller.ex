defmodule CadenceWeb.Console.DataSourceWritesController do
  @moduledoc """
  L11 data-source writes and the reads their screens need (owner: api-ops), under
  `/api/v1/missions/:mission_id`. Contract: docs/apogee/api/setup.md §Data sources (L11).

  Writes go through `OpsConsole.Actions.DataSources`, the adapter the legacy page uses: the same
  validation and authorization (`operate_mission`), and since e80c9d872 only the organization's
  own sources and bindings (platform-shared ones need a platform admin in admin mode:
  `403 platform_source`). Each write answers with the source's D1 row.
  """

  use CadenceWeb, :controller

  require Logger

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.DataSources, as: Actions
  alias Cadence.Auth.Policy
  alias Cadence.Jobs
  alias Cadence.Management.DataSources
  alias Cadence.Reads.DataSourceDirectory
  alias CadenceWeb.Console.{ConfigJSON, Problem}
  alias CadenceWeb.Console.DataSourceRunError, as: RunError

  @kinds [
    %{key: "managed_tsdb", label: "Managed by Cadence", requires_credentials: false},
    %{key: "byo_tsdb", label: "Your own database", requires_credentials: true}
  ]
  @isolation_levels %{
    "shared" => "Shared",
    "org_isolated" => "This organization",
    "mission_isolated" => "This mission",
    "customer_owned" => "Customer-owned"
  }
  @isolation_by_kind %{
    "byo_tsdb" => ~w(customer_owned org_isolated mission_isolated),
    "managed_tsdb" => ~w(shared org_isolated mission_isolated)
  }
  @storages [
    %{key: "questdb", label: "QuestDB"},
    %{key: "postgres_projection", label: "Postgres projection"}
  ]
  @run_kinds %{"provision" => "provision", "deprovision" => "deprovision"}

  # R1
  def options(conn, _params) do
    json(conn, %{
      data: %{
        logical_sources:
          DataSourceDirectory.adapter_labels()
          |> Enum.sort()
          |> Enum.map(fn {key, label} -> %{key: key, label: label} end),
        kinds: @kinds,
        isolation_levels:
          Map.new(@isolation_by_kind, fn {kind, keys} ->
            {kind, Enum.map(keys, &%{key: &1, label: Map.fetch!(@isolation_levels, &1)})}
          end),
        storages: @storages
      }
    })
  end

  # R2
  def show(conn, %{"data_source_id" => id}) do
    case DataSourceDirectory.fetch(org(conn), mission(conn), id) do
      nil ->
        Problem.respond(conn, :data_source_not_found)

      row ->
        json(conn, %{
          data:
            ConfigJSON.encode(%{source: row, bindings: bindings(conn, id), runs: runs(conn, id)})
        })
    end
  end

  # W1: the server makes the id from the name.
  def create(conn, params) do
    name = params |> Map.get("display_name") |> to_string() |> String.trim()

    source =
      params
      |> Map.take(
        ~w(logical_source kind isolation_level storage credentials_ref credential_provider endpoint_ref material_env_profile http_endpoint_env)
      )
      |> Map.merge(%{"data_source_id" => new_id(name), "display_name" => name})

    source =
      Enum.reduce(
        ~w(credentials_ref credential_provider endpoint_ref material_env_profile http_endpoint_env),
        source,
        &Map.update(&2, &1, "", fn value -> value || "" end)
      )

    if name == "" or byte_size(name) > 120 do
      Problem.respond(conn, :invalid_params, %{field: "display_name"})
    else
      conn
      |> act("register-source", %{"source" => source})
      |> respond(conn, :created, source["data_source_id"])
    end
  end

  # W2
  def disable(conn, %{"data_source_id" => id}), do: toggle(conn, id, "disable-source", :disabled)
  def enable(conn, %{"data_source_id" => id}), do: toggle(conn, id, "enable-source", :enabled)

  # W3
  def change_binding(conn, %{"binding_id" => binding_id} = params) do
    target = params["data_source_id"]
    expected = params["expected_data_source_id"]

    case Enum.find(
           DataSources.list_data_bindings(org(conn), mission(conn)),
           &(&1.binding_id == binding_id)
         ) do
      nil ->
        Problem.respond(conn, :binding_not_found)

      # The switch is confirmed against the source the sheet showed; the action checks it (and the
      # write re-checks it under a lock), so the host action path can't skip it either.
      _binding when not is_binary(expected) ->
        Problem.respond(conn, :invalid_params, %{field: "expected_data_source_id"})

      _binding ->
        binding_params =
          params
          |> Map.take(["reason", "expected_affected_missions", "expected_live_passes_total"])
          |> Map.merge(%{
            "binding_id" => binding_id,
            "data_source_id" => to_string(target),
            "expected_data_source_id" => expected
          })

        case act(conn, "change-binding", %{"binding" => binding_params}) do
          # #90: a platform-wide binding answers the counts it recorded.
          {:ok, %{binding: binding, recorded: recorded}} ->
            json(conn, %{
              data: ConfigJSON.encode(%{binding: binding_view(binding), recorded: recorded})
            })

          {:ok, binding} ->
            json(conn, %{data: ConfigJSON.encode(%{binding: binding_view(binding)})})

          error ->
            error(conn, error)
        end
    end
  end

  # W4
  def probe(conn, %{"data_source_id" => id}) do
    case act(conn, "probe-source", %{"data-source-id" => id}) do
      {:ok, %{status: status}} ->
        row = DataSourceDirectory.fetch(org(conn), mission(conn), id)

        json(conn, %{
          data:
            ConfigJSON.encode(%{
              source: row,
              probe: %{health: row && row.health, reason: Map.get(status, :reason)}
            })
        })

      error ->
        error(conn, error)
    end
  end

  # W5
  def credential(conn, %{"data_source_id" => id, "credentials_ref" => ref}) when is_binary(ref),
    do:
      conn
      |> act("rotate-source-credential", %{"data-source-id" => id, "credentials-ref" => ref})
      |> respond(conn, :ok, id)

  def credential(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{field: "credentials_ref"})

  # W6
  def tsdb(conn, %{"data_source_id" => id, "operation" => op})
      when op in ~w(provision reconcile deprovision) do
    case act(conn, op <> "-tsdb-backend", %{"data-source-id" => id}) do
      {:ok, result} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          data:
            ConfigJSON.encode(%{
              source: DataSourceDirectory.fetch(org(conn), mission(conn), id),
              run: result |> Map.get(:job) |> run_view()
            })
        })

      error ->
        error(conn, error)
    end
  end

  def tsdb(conn, _params), do: Problem.respond(conn, :not_found)

  # W7
  def run_action(conn, %{"job_id" => job_id, "action" => action})
      when action in ~w(retry requeue) do
    case act(conn, action <> "-deployment-run", %{"job-id" => job_id}) do
      # Retry and requeue answer the run's job wrapped with its deployment status (qa L11 (D)).
      {:ok, %{job: %Jobs.Job{} = job}} ->
        conn |> put_status(:accepted) |> json(%{data: ConfigJSON.encode(%{run: run_view(job)})})

      {:ok, %Jobs.Job{} = job} ->
        conn |> put_status(:accepted) |> json(%{data: ConfigJSON.encode(%{run: run_view(job)})})

      {:ok, _other} ->
        conn |> put_status(:accepted) |> json(%{data: %{run: nil}})

      {:error, reason} when reason in [:job_not_found, :not_found] ->
        Problem.respond(conn, :run_not_found)

      error ->
        error(conn, error)
    end
  end

  def run_action(conn, _params), do: Problem.respond(conn, :not_found)

  @doc "D1's permissions: what the writes check (operate_mission today)."
  def permissions(scope, mission_id) do
    # todo(authz): Cedar should decide who may manage data sources (any mission operator today).
    if Policy.authorize(scope, :operate_mission, %{
         organization_id: scope.organization_id,
         mission_id: mission_id
       }) == :ok,
       do: ["data_sources.manage"],
       else: []
  end

  defp toggle(conn, id, action, wanted) do
    case DataSourceDirectory.fetch(org(conn), mission(conn), id) do
      nil -> Problem.respond(conn, :data_source_not_found)
      %{state: ^wanted} -> Problem.respond(conn, :data_source_state, %{state: wanted})
      _row -> conn |> act(action, %{"data-source-id" => id}) |> respond(conn, :ok, id)
    end
  end

  defp act(conn, action_id, params) do
    Actions.execute(
      conn.assigns.current_scope,
      HostContext.mission(mission(conn)),
      "data_sources",
      %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "data_sources",
        surface_version: 1,
        action_id: action_id,
        params: params
      }
    )
  end

  defp respond({:ok, _result}, conn, status, id) do
    conn
    |> put_status(status)
    |> json(%{
      data: ConfigJSON.encode(%{source: DataSourceDirectory.fetch(org(conn), mission(conn), id)})
    })
  end

  defp respond(error, conn, _status, _id), do: error(conn, error)

  defp error(conn, {:error, :platform_source}), do: Problem.respond(conn, :platform_source)
  defp error(conn, {:error, :scope_mismatch}), do: Problem.respond(conn, :data_source_not_found)

  defp error(conn, {:error, :same_data_source}),
    do: Problem.respond(conn, :data_source_state, %{state: "already_bound"})

  # L11 (qa): provision/reconcile/deprovision on a source whose backend Cadence doesn't manage.
  # The source read's tsdb_actions lists what a source takes, so the page doesn't offer these.
  defp error(conn, {:error, :byo_tsdb_backend_required}),
    do:
      tsdb_refusal(
        conn,
        "managed",
        "This source is managed by Cadence; its storage is provisioned automatically."
      )

  defp error(conn, {:error, :dedicated_tsdb_backend_required}),
    do:
      tsdb_refusal(
        conn,
        "customer_owned",
        "This source uses your own database as is; Cadence doesn't provision it."
      )

  # W5: a reference another source or mission already uses can't be rotated to.
  defp error(conn, {:error, :credential_reference_in_use}),
    do: Problem.respond(conn, :invalid_params, %{field: "credentials_ref"})

  # #90 / U53: a platform-wide switch needs a reason and the counts the sheet showed.
  defp error(conn, {:error, {:invalid, field, sentence}}),
    do: Problem.respond(conn, :invalid_params, %{"field" => field, field => sentence})

  defp error(conn, {:error, {:blast_radius_changed, fresh}}),
    do: Problem.respond(conn, :blast_radius_changed, ConfigJSON.encode(fresh))

  defp error(conn, {:error, :blast_radius_unavailable}),
    do: Problem.respond(conn, :blast_radius_unavailable)

  defp error(conn, {:error, :env_credential_name_not_allowed}),
    do:
      Problem.respond(conn, :invalid_params, %{
        field: "http_endpoint_env",
        http_endpoint_env:
          "This environment doesn't allow that variable for a source. Ask a platform admin."
      })

  defp error(conn, {:error, :env_material_profile_not_allowed}),
    do:
      Problem.respond(conn, :invalid_params, %{
        field: "material_env_profile",
        material_env_profile: "That credential profile isn't this organization's."
      })

  defp error(conn, {:error, :platform_target_required}),
    do: Problem.respond(conn, :platform_target_required, %{field: "data_source_id"})

  defp error(conn, {:error, :incompatible_data_source}),
    do: Problem.respond(conn, :invalid_params, %{field: "data_source_id"})

  defp error(conn, {:error, {:binding_changed, current}}),
    do: Problem.respond(conn, :binding_changed, %{current_data_source_id: current})

  defp error(conn, {:error, :malformed_action_input}), do: Problem.respond(conn, :invalid_params)

  defp error(conn, {:error, reason}) when reason in [:forbidden, :authenticated_user_required],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, {:error, [{_field, _message} | _] = errors}),
    do: Problem.respond(conn, :invalid_params, %{field: errors |> hd() |> elem(0) |> to_string()})

  defp error(conn, error) do
    Logger.warning("data source write failed: #{inspect(error, limit: 20)}")
    Problem.respond(conn, :data_source_unavailable)
  end

  defp tsdb_refusal(conn, state, message) do
    conn
    |> put_status(409)
    |> json(Problem.body("data_source_state", message, %{state: state}))
  end

  defp bindings(conn, id) do
    org(conn)
    |> DataSources.list_data_bindings(mission(conn))
    |> Enum.filter(&(&1.data_source_id == id))
    |> Enum.map(&binding_view/1)
  end

  defp binding_view(binding),
    do: %{
      id: binding.binding_id,
      logical_source: binding.logical_source,
      data_source_id: binding.data_source_id,
      status: binding.status,
      # #90: a platform-wide binding (no organization); Switch… opens the danger sheet.
      shared: is_nil(binding.organization_id)
    }

  defp runs(conn, id) do
    org(conn)
    |> Jobs.source_deployment_page(mission(conn), id, 1)
    |> Map.fetch!(:entries)
    |> Enum.take(20)
    |> Enum.map(&run_view/1)
  end

  defp run_view(nil), do: nil

  defp run_view(%Jobs.Job{} = job) do
    payload = unwrap(job.payload)
    operation = to_string(payload["operation"] || "")

    %{
      job_id: job.job_id,
      kind:
        Map.get(
          @run_kinds,
          operation,
          if(job.job_type == :managed_questdb_provisioning, do: "provision", else: "reconcile")
        ),
      status: job.status,
      started_at: job.started_at,
      error: RunError.view(job.failure_reason),
      actions:
        case job.status do
          :failed -> ["retry"]
          :running -> ["requeue"]
          _other -> []
        end
    }
  end

  defp new_id(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> String.slice(0, 60)
      |> then(&if(&1 == "", do: "source", else: &1))

    Enum.find(Stream.concat([base], Stream.map(2..1000, &"#{base}_#{&1}")), fn id ->
      match?({:error, _}, DataSources.fetch_data_source(id))
    end)
  end

  defp unwrap(%{"value" => value}) when is_map(value), do: value
  defp unwrap(value) when is_map(value), do: value
  defp unwrap(_value), do: %{}

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
