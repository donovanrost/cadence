defmodule Cadence.Runtime.Reconciliation.Supervisor do
  @moduledoc """
  Supervision tree for the reconciliation infrastructure.

  This supervisor manages:
  - Registry for OrgReconciler lookup by org_id
  - Task supervisor for parallel mission reconciliation
  - DynamicSupervisor for OrgReconciler processes
  - ReconcilerManager that maintains OrgReconcilers via periodic reconciliation

  ## Architecture

  ```
  Reconciliation.Supervisor
  ├── ReconcilerRegistry (Registry)
  ├── ReconcilerTaskSupervisor (Task.Supervisor)
  ├── OrgReconcilerSupervisor (DynamicSupervisor)
  └── ReconcilerManager (GenServer)
        └── starts/stops OrgReconcilers via OrgReconcilerSupervisor
  ```

  The ReconcilerManager uses the same reconciliation pattern to manage
  OrgReconcilers - reconcilers all the way down.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for OrgReconciler lookup by org_id
      {Registry, keys: :unique, name: Cadence.ReconcilerRegistry},

      # Task supervisor for parallel mission reconciliation within OrgReconcilers
      {Task.Supervisor, name: Cadence.ReconcilerTaskSupervisor},

      # Dynamic supervisor for OrgReconciler processes
      {DynamicSupervisor, name: Cadence.OrgReconcilerSupervisor, strategy: :one_for_one},

      # Manager that reconciles the set of OrgReconcilers
      {Cadence.Runtime.Reconciliation.Manager, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
