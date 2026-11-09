defmodule Cadence.ContactPlanning.FleetPlanningPolicySchema do
  @moduledoc """
  Field schema for the fleet planning policy document (console CP2), in the
  kind-schema field shape plus `group` and `advanced`. Bounds and defaults
  mirror `Cadence.ContactPlanning.FleetPlanningPolicyDocument`, which remains
  the validator. Paths are `<group>.<field>`, matching the wire document
  `%{"horizon" => …, "scoring" => …, "resources" => …, "budgets" => …,
  "redundancy" => …, "automation" => …}`.
  """

  @day 86_400
  @max_horizon 31 * @day

  @doc "Wire group key → policy version attribute."
  @spec groups() :: [{binary(), atom()}]
  def groups,
    do: [
      {"horizon", :horizon_document},
      {"scoring", :scoring_document},
      {"resources", :resource_policy_document},
      {"budgets", :budget_quota_document},
      {"redundancy", :redundancy_document},
      {"automation", :automation_repair_document}
    ]

  @spec fields() :: [map()]
  def fields do
    horizon() ++ scoring() ++ resources() ++ budgets() ++ redundancy() ++ automation()
  end

  @doc "The defaults document (what the domain fills in for omitted fields)."
  @spec defaults() :: map()
  def defaults do
    Enum.reduce(fields(), %{}, fn field, acc ->
      [group, key] = String.split(field.path, ".", parts: 2)
      Map.update(acc, group, %{key => field.default}, &Map.put(&1, key, field.default))
    end)
  end

  defp horizon do
    [
      int("horizon.max_horizon_seconds", "Longest planning window", @day * 7, 60, @max_horizon,
        unit: "s"
      ),
      int("horizon.requirement_concurrency", "Requirements searched in parallel", 8, 1, 64,
        advanced: true
      ),
      int("horizon.provider_search_concurrency", "Provider searches in parallel", 4, 1, 64,
        advanced: true
      ),
      int("horizon.reuse_freshness_seconds", "Reuse searches newer than", 0, 0, @max_horizon,
        unit: "s",
        advanced: true
      )
    ]
  end

  defp scoring do
    weights = [
      {"priority_weight", "Priority", 1_000},
      {"deadline_weight", "Deadline", 800},
      {"scarcity_weight", "Scarcity", 600},
      {"preferred_duration_weight", "Preferred duration", 300},
      {"volume_weight", "Data volume", 300},
      {"confidence_weight", "Confidence", 200},
      {"cost_efficiency_weight", "Cost efficiency", 100},
      {"diversity_weight", "Diversity", 200},
      {"fragmentation_penalty", "Fragmentation penalty", 100},
      {"expiry_risk_penalty", "Expiry risk penalty", 200}
    ]

    Enum.map(weights, fn {key, label, default} ->
      int("scoring." <> key, label <> " weight", default, 0, 10_000, advanced: true)
    end) ++
      [
        int("scoring.local_improvement_limit", "Local improvement steps", 100, 0, 10_000,
          advanced: true
        ),
        int("scoring.local_improvement_width", "Local improvement width", 3, 1, 8, advanced: true)
      ]
  end

  defp resources do
    [
      int("resources.default_exclusive_capacity", "Passes per antenna at once", 1, 1, 1_000,
        help: "Applies to every antenna. Limits for individual antennas can't be set here yet."
      )
    ]
  end

  defp budgets do
    [
      int("budgets.max_contacts", "Contacts per plan (cap)", nil, 1, 1_000_000,
        help: "Empty means no cap."
      ),
      int(
        "budgets.max_estimated_cost_micros",
        "Cost per plan (cap)",
        nil,
        0,
        9_000_000_000_000_000,
        unit: "micros",
        help: "Empty means no cap; needs a currency."
      ),
      field("budgets.currency", "Currency", :string, nil,
        help: "Three-letter currency code, for example USD."
      ),
      int(
        "budgets.critical_contact_reserve",
        "Contacts reserved for critical needs",
        0,
        0,
        1_000_000,
        advanced: true
      ),
      int(
        "budgets.critical_cost_reserve_micros",
        "Cost reserved for critical needs",
        0,
        0,
        9_000_000_000_000_000,
        unit: "micros",
        advanced: true
      )
    ]
  end

  defp redundancy do
    [
      field(
        "redundancy.distinct_provider_required",
        "Different provider for redundant passes",
        :boolean,
        false
      ),
      field(
        "redundancy.distinct_station_required",
        "Different station for redundant passes",
        :boolean,
        false
      ),
      field(
        "redundancy.distinct_service_pool_required",
        "Different antenna pool for redundant passes",
        :boolean,
        false,
        advanced: true
      )
    ]
  end

  defp automation do
    [
      field("automation.mode", "Repair automation", :enum, "advisory",
        enum: [
          %{value: "advisory", label: "Advise only"},
          %{value: "approval_required", label: "Propose for approval"},
          %{value: "bounded_automatic", label: "Repair automatically (bounded)"}
        ]
      ),
      int("automation.execution_concurrency", "Bookings in parallel", 4, 1, 64, advanced: true),
      int("automation.max_repair_attempts", "Repair attempts per plan", 3, 0, 100),
      int("automation.repair_horizon_seconds", "Repair window", @day, 60, @max_horizon,
        unit: "s"
      ),
      field("automation.automatic_submission", "Submit repairs automatically", :boolean, false,
        help: "Only with bounded automatic mode.",
        visible_when: %{path: "automation.mode", equals: "bounded_automatic"}
      )
    ]
  end

  defp int(path, label, default, min, max, opts \\ []),
    do: field(path, label, :integer, default, Keyword.put(opts, :range, %{min: min, max: max}))

  defp field(path, label, type, default, opts \\ []) do
    [group | _] = String.split(path, ".")

    %{
      path: path,
      label: label,
      type: type,
      unit: Keyword.get(opts, :unit),
      enum: Keyword.get(opts, :enum),
      range: Keyword.get(opts, :range),
      default: default,
      required: false,
      help: Keyword.get(opts, :help),
      visible_when: Keyword.get(opts, :visible_when),
      group: group,
      advanced: Keyword.get(opts, :advanced, false)
    }
  end
end
