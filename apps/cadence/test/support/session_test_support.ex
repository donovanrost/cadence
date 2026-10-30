defmodule Cadence.SessionTestSupport do
  @moduledoc false
  @behaviour Cadence.Runtime.SessionQualification
  alias Cadence.Platform.RootComposition
  alias Cadence.Runtime.{MissionRuntime, ProcessNamespace, TransportRuntime}

  # This policy exists only in test/support. It is not a TCP qualification.
  def verify_fencing(_basis, %{reference: "test-only:fencing"}), do: :ok
  def verify_fencing(_, _), do: {:error, :test_fencing_required}
  def verify_protocol_recovery(_basis, _fencing, %{reference: "test-only:protocol"}), do: :ok
  def verify_protocol_recovery(_, _, _), do: {:error, :test_recovery_required}

  def verify_recovery_exchange(_, _, %{purpose: "test-recovery"}, %{
        reference: "test-only:exchange"
      }),
      do: :ok

  def verify_recovery_exchange(_, _, _, _), do: {:error, :test_exchange_required}

  def evidence(review, kind),
    do: %{
      basis_sha256: review.basis_sha256,
      reference: "test-only:#{kind}",
      valid_until: DateTime.add(DateTime.utc_now(), 60, :second)
    }

  def install_default_policy! do
    {:ok, original} = :supervisor.get_childspec(Cadence.Supervisor, Cadence.Runtime.Supervisor)

    replace_root(
      {Cadence.Runtime.Supervisor,
       root_composition: RootComposition.from_application(uplink_session_policy: __MODULE__)}
    )

    ExUnit.Callbacks.on_exit(fn -> replace_root(original) end)
  end

  defp replace_root(spec) do
    :ok = Supervisor.terminate_child(Cadence.Supervisor, Cadence.Runtime.Supervisor)
    :ok = Supervisor.delete_child(Cadence.Supervisor, Cadence.Runtime.Supervisor)
    {:ok, _} = Supervisor.start_child(Cadence.Supervisor, spec)
  end

  def ready!(mission, contact, path, binding) do
    runtime =
      GenServer.whereis(
        MissionRuntime.transport_runtime_name(
          ProcessNamespace.default(),
          mission,
          contact,
          path,
          binding
        )
      )

    {:ok, review} = TransportRuntime.session_review(runtime)
    :ok = TransportRuntime.begin_session_recovery(runtime, evidence(review, :fencing))
    {:ok, review} = TransportRuntime.session_review(runtime)
    :ok = TransportRuntime.complete_session_recovery(runtime, evidence(review, :protocol))
    runtime
  end
end
