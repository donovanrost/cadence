defmodule Cadence.Platform.ConfigKind do
  @moduledoc """
  Contract between mission change sets and one kind of governed setup entity.

  A kind translates its entity to and from a canonical **document**: a JSON-safe map with string
  keys. Change sets stage edits against documents, diff them, detect conflicts by value and keep
  before/after documents in the revision ledger. The kind owns validation and persistence.

  ## Side-effect rule

  `validate/6` and `write/7` run inside a database transaction. During a preview that transaction
  is rolled back, so they must only read and write through `Cadence.Repo`. They must not
  broadcast, call processes, spawn tasks or emit telemetry. Everything observable outside the
  database happens in the change set's after-commit tail, driven by `runtime_impact/3`.
  """

  @type document :: %{optional(String.t()) => term()}
  @type action :: :create | :update | :delete
  @type field_error :: %{path: String.t(), message: String.t()}
  @type entry :: %{
          kind: String.t(),
          entity_id: String.t(),
          op: action(),
          previous: document() | nil,
          proposed: document() | nil
        }

  @doc "Stable kind key, e.g. `\"ground_station\"`."
  @callback kind() :: String.t()

  @doc "Prefix used when the change set mints an id for a created entity."
  @callback id_prefix() :: String.t()

  @doc "Current documents for the given ids. Missing or archived entities are absent from the map."
  @callback load(organization_id :: String.t(), mission_id :: String.t(), [String.t()]) ::
              %{String.t() => document()}

  @doc """
  Shape and field validation of a proposed document, without cross-entity checks.
  Used when staging. Returns the normalized document.
  """
  @callback normalize(action(), entity_id :: String.t(), document() | nil) ::
              {:ok, document() | nil} | {:error, [field_error()]}

  @doc "Full validation of a transition against the current database state (references, uniqueness)."
  @callback validate(
              organization_id :: String.t(),
              mission_id :: String.t(),
              action(),
              entity_id :: String.t(),
              previous :: document() | nil,
              proposed :: document() | nil
            ) :: :ok | {:error, [field_error()]}

  @doc """
  Persists the transition. Returns the stored document plus any further entity changes the write
  caused (for example spacecraft moved to a new profile version), so they enter the ledger too.
  """
  @callback write(
              organization_id :: String.t(),
              mission_id :: String.t(),
              action(),
              entity_id :: String.t(),
              previous :: document() | nil,
              proposed :: document() | nil,
              options :: map()
            ) :: {:ok, document() | nil, [entry()]} | {:error, term()}

  @doc "One-line human summary of the change."
  @callback summary(action(), previous :: document() | nil, proposed :: document() | nil) ::
              String.t()

  @doc "What the after-commit tail must notify."
  @callback runtime_impact(action(), previous :: document() | nil, proposed :: document() | nil) ::
              :generation | :contacts | :none

  @doc "Per-spacecraft effect of the change, for previews (`changes N · keeps M`)."
  @callback effect(
              organization_id :: String.t(),
              mission_id :: String.t(),
              action(),
              entity_id :: String.t(),
              previous :: document() | nil,
              proposed :: document() | nil,
              options :: map()
            ) :: %{changes: non_neg_integer(), keeps: [map()]} | nil

  @doc """
  Validates op options that are not part of the document (e.g. a profile edit's rollout).
  Kinds without options don't implement it, and staging refuses options for them.
  """
  @callback normalize_options(action(), map()) :: {:ok, map()} | {:error, [field_error()]}

  @doc """
  Runs once after every op of a run has been written, in the same transaction. A kind that
  derives state from other kinds (for example routes from profiles, pins and overrides) brings
  it in line here and returns the changes as ledger entries, plus what the after-commit tail
  must notify. Field errors make the run a NO-GO.
  """
  @callback finalize(organization_id :: String.t(), mission_id :: String.t(), [entry()]) ::
              {:ok, [entry()], [:generation | :contacts]} | {:error, [field_error()]}

  @doc """
  Compatibility HOLDs for a run, after finalize: things that will apply but deserve an explicit
  acknowledgement (e.g. framing that will change decode). Read-only.
  """
  @callback holds(organization_id :: String.t(), mission_id :: String.t(), [entry()]) :: [map()]

  @doc """
  Runs after the change set has committed, with this kind's entries of the applied run: the
  place to announce what changed outside the database (e.g. limit facts), since `write/7` and
  `finalize/3` run inside the transaction (and a preview rolls it back). Never runs for a
  preview. A failure leaves the revision applied and the runtime reported degraded.
  """
  @callback after_commit(organization_id :: String.t(), mission_id :: String.t(), [entry()]) ::
              :ok

  @doc """
  The entity id a create gets, when the kind's ids follow from the document (a limit
  definition's is its point and limit set's). Without it, creates get a fresh `id_prefix/0` id.
  When that id is live already, staging calls `validate/6` with the live document as `previous`
  so the kind words the refusal.
  """
  @callback create_entity_id(document()) :: String.t()

  @doc """
  Refuses an update or delete at STAGE (nothing staged) with a reason the API carries as is, e.g.
  `{:in_use, uses}`. `deleting` is what this stage and the open set delete beside it, as
  `{kind, entity_id}`. The same rule belongs in validate/6 too, which re-runs at preview and apply.
  """
  @callback stage_check(
              String.t(),
              String.t(),
              :update | :delete,
              String.t(),
              deleting :: MapSet.t({String.t(), String.t()})
            ) :: :ok | {:error, term()}

  @doc """
  Why an entity this kind doesn't load (nothing current) can't be changed, as field errors:
  staging refuses an update or delete of it with these instead of "This no longer exists".
  """
  @callback absent_errors(organization_id :: String.t(), mission_id :: String.t(), String.t()) ::
              [field_error()]

  @doc """
  Refuses ops of this STAGE request against what the change set already has staged, under the
  set lock (nothing is staged on a refusal): e.g. a SCID another spacecraft's staged op holds
  (S9). `staged` is the set's staged ops after this author's overlapping ones are replaced;
  `prepared` is the request's ops in order, so the error's index is the request's. A kind sees
  every op and picks its own.
  """
  @callback stage_conflicts(
              organization_id :: String.t(),
              mission_id :: String.t(),
              staged :: [map()],
              prepared :: [map()]
            ) :: :ok | {:error, {:invalid_op, non_neg_integer(), [field_error()]}}

  @doc """
  Rewrites a staged document before `normalize/3`, with the tenant in hand, AT STAGING ONLY (never
  at apply): e.g. D3's translation of an old client's `catalog_revision_id` to the composition it
  names (#544). `previous` is the live document (nil for a create), `touched` the paths the op
  sets. Paths it changes beyond `touched` are staged as further changes, so the staged op names
  exactly what apply will write.
  """
  @callback translate(
              String.t(),
              String.t(),
              previous :: document() | nil,
              proposed :: document(),
              touched :: [String.t()]
            ) :: {:ok, document()} | {:error, [field_error()]}

  @optional_callbacks stage_check: 5,
                      stage_conflicts: 4,
                      translate: 5,
                      absent_errors: 3,
                      effect: 7,
                      normalize_options: 2,
                      finalize: 3,
                      holds: 3,
                      after_commit: 3,
                      create_entity_id: 1
end
