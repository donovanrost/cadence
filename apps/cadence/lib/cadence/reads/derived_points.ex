defmodule Cadence.Reads.DerivedPoints do
  @moduledoc """
  The operator points a revision's algorithms derive (#451 T4b): one per algorithm output, beside
  the packet fields in `Cadence.Ops.PointCatalog`.

  An output is a real `:parameter` declaration of the revision, and its id is that parameter's
  semantic id, stable across revisions. The partition persists each computed value as a sample
  whose `point_id` is that id (`PartitionOwner` `derived_sample/2`), so the point id here is the
  semantic id too. Every spacecraft on the revision computes its own value; the point is one
  definition, not one per craft.

    * The outputs come from the revision's compiled algorithm plan (`MissionModels.fetch_plan/4`).
    * The type and unit come from the output parameter's declaration in the revision, through
      `parameter -> type -> unit` (`Reads.CatalogDeclarations`, the same read packet points fall
      back to).
    * `space_system_id` is the system that owns the algorithm that computes it, as the plan
      carries it (nil for a plan compiled before ADR-020 P5).

  **Cost.** A revision's plans and declarations never change, so a revision's derived points are
  built once per node (one plan read and up to three declaration reads, whatever the fleet size)
  and kept in an ETS table owned by this process, newest #{16} revisions only. A read is one ETS
  lookup. Without the process (a unit test that does not start the application) every read builds.
  """

  use GenServer

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.MissionModels
  alias Cadence.Reads.CatalogDeclarations

  @table __MODULE__
  @keep 16

  @data_types %{
    "integer" => :int,
    "float" => :float,
    "boolean" => :bool,
    "enumerated" => :enum,
    "string" => :string,
    "binary" => :binary
  }

  @type point :: %{
          point_id: binary(),
          parameter_id: binary(),
          qualified_name: binary(),
          name: binary(),
          packet_name: nil,
          field_name: nil,
          unit: binary() | nil,
          data_type: atom() | nil,
          base_type: binary() | nil,
          space_system_id: binary() | nil,
          source: :derived,
          stale_timeout_ms: nil,
          description: nil
        }

  @doc "The derived points of `revision_id` (`[]` for `nil` or a revision without algorithms)."
  @spec list(binary(), binary(), binary() | nil) :: [point()]
  def list(_organization_id, _mission_id, nil), do: []

  def list(organization_id, mission_id, revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) do
    cached({organization_id, mission_id, revision_id}, fn ->
      build(organization_id, mission_id, revision_id)
    end)
  end

  defp build(organization_id, mission_id, revision_id) do
    case MissionModels.fetch_plan(organization_id, mission_id, revision_id, :algorithm) do
      {:ok, %RuntimePlan{status: :ready, plan: plan}} ->
        outputs = outputs(plan)

        declarations =
          CatalogDeclarations.closure(
            organization_id,
            mission_id,
            revision_id,
            Enum.map(outputs, & &1.parameter_id)
          )

        outputs
        |> Enum.map(&point(&1, declarations))
        |> Enum.sort_by(&{&1.qualified_name, &1.point_id})

      _no_plan ->
        []
    end
  end

  # One entry per output parameter; the compiler refuses a parameter with two producers.
  defp outputs(plan) do
    for algorithm <- List.wrap(field(plan, :algorithms)),
        output <- List.wrap(field(algorithm, :outputs)),
        is_binary(field(output, :parameter_id)) do
      %{
        parameter_id: field(output, :parameter_id),
        qualified_name: field(output, :qualified_name),
        space_system_id: field(algorithm, :space_system_id)
      }
    end
    |> Enum.uniq_by(& &1.parameter_id)
  end

  defp point(output, declarations) do
    declaration = Map.get(declarations, output.parameter_id, %{})
    qualified_name = field(declaration, :qualified_name) || output.qualified_name
    base_type = CatalogDeclarations.parameter_base_type(declarations, output.parameter_id)

    %{
      point_id: output.parameter_id,
      parameter_id: output.parameter_id,
      qualified_name: qualified_name,
      name: qualified_name || output.parameter_id,
      packet_name: nil,
      field_name: nil,
      unit: CatalogDeclarations.parameter_unit(declarations, output.parameter_id),
      data_type: Map.get(@data_types, base_type),
      base_type: base_type,
      space_system_id: output.space_system_id,
      source: :derived,
      stale_timeout_ms: nil,
      description: nil
    }
  end

  defp field(%{} = map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_other, _key), do: nil

  defp cached(key, build) do
    case :ets.whereis(@table) do
      :undefined ->
        build.()

      _table ->
        case :ets.lookup(@table, key) do
          [{^key, _at, points}] ->
            points

          [] ->
            points = build.()
            GenServer.cast(__MODULE__, {:put, key, points})
            points
        end
    end
  end

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, key, points}, state) do
    :ets.insert(@table, {key, System.monotonic_time(), points})

    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.drop(@keep)
    |> Enum.each(&:ets.delete(@table, elem(&1, 0)))

    {:noreply, state}
  end
end
