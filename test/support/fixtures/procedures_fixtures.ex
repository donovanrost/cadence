defmodule Cadence.ProceduresFixtures do
  @moduledoc """
  Test fixtures for the Procedures context.
  """

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.AccountsFixtures

  alias Cadence.Procedures

  @doc """
  Creates a procedure fixture.
  """
  def procedure_fixture(attrs \\ %{}) do
    org = attrs[:organization] || organization_fixture()
    mission = attrs[:mission] || mission_fixture(organization: org)
    user = attrs[:user] || user_fixture()

    source = attrs[:source] || default_dag_source()

    procedure_attrs = %{
      organization_id: org.id,
      mission_id: mission.id,
      name: attrs[:name] || "Test Procedure #{System.unique_integer([:positive])}",
      description: attrs[:description] || "A test procedure",
      type: attrs[:type] || :dag
    }

    procedure_attrs =
      if attrs[:tags], do: Map.put(procedure_attrs, :tags, attrs[:tags]), else: procedure_attrs

    {:ok, procedure} =
      Procedures.create_procedure(
        procedure_attrs,
        source: source,
        user_id: user.id
      )

    procedure
  end

  @doc """
  Creates a script procedure fixture.
  """
  def script_procedure_fixture(attrs \\ %{}) do
    source = attrs[:source] || %{"code" => "cadence.log('Hello from Lua!')"}

    procedure_fixture(Map.merge(attrs, %{type: :script, source: source}))
  end

  @doc """
  Creates a procedure with approved version.
  """
  def approved_procedure_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    procedure = procedure_fixture(attrs)

    version = Procedures.get_version!(procedure.current_version_id)
    {:ok, _} = Procedures.approve_version(version, user.id)

    Procedures.get_procedure!(procedure.id)
  end

  @doc """
  Default DAG source with basic steps.
  """
  def default_dag_source do
    %{
      "steps" => %{
        "step_1" => %{
          "type" => "log",
          "message" => "Starting procedure",
          "depends_on" => []
        },
        "step_2" => %{
          "type" => "wait",
          "duration" => 100,
          "depends_on" => ["step_1"]
        },
        "step_3" => %{
          "type" => "log",
          "message" => "Procedure complete",
          "depends_on" => ["step_2"]
        }
      }
    }
  end

  @doc """
  Creates a DAG with a check step.
  """
  def dag_with_check_source(condition, on_fail \\ "abort") do
    %{
      "steps" => %{
        "check_step" => %{
          "type" => "check",
          "condition" => condition,
          "on_fail" => on_fail,
          "message" => "Check failed: #{condition}",
          "depends_on" => []
        },
        "log_step" => %{
          "type" => "log",
          "message" => "Check passed",
          "depends_on" => ["check_step"]
        }
      }
    }
  end

  @doc """
  Creates a procedure execution fixture.
  """
  def execution_fixture(attrs \\ %{}) do
    procedure = attrs[:procedure] || procedure_fixture()
    user = attrs[:user]

    {:ok, execution} =
      Procedures.create_execution(%{
        procedure_id: procedure.id,
        procedure_version_id: procedure.current_version_id,
        organization_id: procedure.organization_id,
        mission_id: procedure.mission_id,
        target_id: attrs[:target_id],
        parameters: attrs[:parameters] || %{},
        triggered_by: attrs[:triggered_by] || :manual,
        triggered_by_user_id: user && user.id
      })

    # Optionally update status and completed_steps for testing specific states
    if attrs[:status] || attrs[:completed_steps] do
      status_attrs = %{}
      |> maybe_add(:status, attrs[:status])
      |> maybe_add(:completed_steps, attrs[:completed_steps])
      |> maybe_add(:failed_steps, attrs[:failed_steps])
      |> maybe_add(:skipped_steps, attrs[:skipped_steps])
      |> maybe_add(:blocked_steps, attrs[:blocked_steps])
      |> maybe_add(:current_step_index, attrs[:current_step_index])
      |> maybe_add(:started_at, attrs[:started_at])

      {:ok, execution} = Procedures.update_execution_status(execution, status_attrs)
      execution
    else
      execution
    end
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
