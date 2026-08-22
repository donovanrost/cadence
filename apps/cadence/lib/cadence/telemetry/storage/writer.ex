defmodule Cadence.Telemetry.Storage.Writer do
  @moduledoc """
  Behaviour for telemetry observation history writers.

  Writers receive storage-neutral observation envelopes. They may persist them to
  QuestDB, Postgres-backed read models, object storage, or a test sink, but they
  do not decide observation identity.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil
  @callback persist_envelopes([ObservationEnvelope.t()], keyword()) :: :ok | {:error, term()}
end
