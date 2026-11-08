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

  @optional_callbacks effect: 7, normalize_options: 2
end
