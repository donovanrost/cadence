defmodule Cadence.Test.Adapters.FakeEmailSender do
  @moduledoc """
  Fake email sender for testing.

  Implements `Cadence.Ports.Communication.EmailSender` behavior by collecting
  sent emails in an Agent, allowing tests to assert on what emails were sent.

  ## Usage

      setup do
        {:ok, pid} = FakeEmailSender.start_link()
        on_exit(fn -> FakeEmailSender.stop(pid) end)
        {:ok, email_sender: pid}
      end

      test "sends welcome email", %{email_sender: pid} do
        # ... trigger action that sends email ...

        emails = FakeEmailSender.get_emails(pid)
        assert length(emails) == 1
        assert hd(emails).subject == "Welcome!"
      end

  ## With Application Config

  For use with the DI system:

      # In test setup
      Application.put_env(:cadence, :email_sender, Cadence.Test.Adapters.FakeEmailSender)
  """

  use Agent

  @behaviour Cadence.Ports.Communication.EmailSender

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  @doc """
  Starts the fake email sender agent.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> [] end, name: name)
  end

  @doc """
  Stops the fake email sender agent.
  """
  def stop(pid \\ __MODULE__) do
    Agent.stop(pid)
  end

  # ============================================================================
  # Behaviour Implementation
  # ============================================================================

  @impl true
  def send_email(email) do
    Agent.update(__MODULE__, fn emails ->
      [normalize_email(email) | emails]
    end)

    {:ok, %{message_id: Ecto.UUID.generate(), status: :sent}}
  end

  @impl true
  def send_email_async(email) do
    Agent.update(__MODULE__, fn emails ->
      [normalize_email(email) | emails]
    end)

    :ok
  end

  @impl true
  def send_batch(emails) do
    Enum.map(emails, &send_email/1)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all emails that have been "sent".

  Emails are returned in reverse chronological order (most recent first).
  """
  def get_emails(pid \\ __MODULE__) do
    Agent.get(pid, & &1)
  end

  @doc """
  Returns the most recently sent email.
  """
  def last_email(pid \\ __MODULE__) do
    Agent.get(pid, fn emails ->
      List.first(emails)
    end)
  end

  @doc """
  Returns the count of sent emails.
  """
  def sent_count(pid \\ __MODULE__) do
    Agent.get(pid, &length/1)
  end

  @doc """
  Clears all collected emails.
  """
  def clear(pid \\ __MODULE__) do
    Agent.update(pid, fn _ -> [] end)
  end

  @doc """
  Finds emails matching the given criteria.

  ## Examples

      FakeEmailSender.find_emails(to: "user@example.com")
      FakeEmailSender.find_emails(subject: ~r/welcome/i)
  """
  def find_emails(criteria, pid \\ __MODULE__) do
    Agent.get(pid, fn emails ->
      Enum.filter(emails, &email_matches?(&1, criteria))
    end)
  end

  defp email_matches?(email, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      email_value = Map.get(email, key)
      matches?(email_value, value)
    end)
  end

  @doc """
  Asserts that an email was sent matching the criteria.

  Raises if no matching email is found.
  """
  def assert_email_sent(criteria, pid \\ __MODULE__) do
    case find_emails(criteria, pid) do
      [] ->
        all_emails = get_emails(pid)

        raise ExUnit.AssertionError,
          message: """
          Expected an email matching #{inspect(criteria)} to have been sent.

          Emails sent: #{inspect(all_emails, pretty: true)}
          """

      emails ->
        emails
    end
  end

  @doc """
  Asserts that no emails were sent.
  """
  def assert_no_emails(pid \\ __MODULE__) do
    case get_emails(pid) do
      [] ->
        :ok

      emails ->
        raise ExUnit.AssertionError,
          message: """
          Expected no emails to have been sent.

          Emails sent: #{inspect(emails, pretty: true)}
          """
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_email(email) when is_map(email) do
    %{
      to: Map.get(email, :to),
      subject: Map.get(email, :subject),
      body: Map.get(email, :body),
      html_body: Map.get(email, :html_body),
      from: Map.get(email, :from),
      reply_to: Map.get(email, :reply_to),
      cc: Map.get(email, :cc),
      bcc: Map.get(email, :bcc),
      sent_at: DateTime.utc_now()
    }
  end

  defp matches?(value, %Regex{} = regex), do: Regex.match?(regex, to_string(value))
  defp matches?(value, expected), do: value == expected
end
