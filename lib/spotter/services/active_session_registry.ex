defmodule Spotter.Services.ActiveSessionRegistry do
  @moduledoc false
  use GenServer

  require Logger

  @table __MODULE__
  @sweep_interval 15_000
  @ttl_seconds 90

  # ETS record: {session_id, pane_id, last_hook_at, ended_at, ended_reason, status}
  # status: :active | :ended

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Register a new active session.
  """
  def start_session(session_id, pane_id) do
    now = System.monotonic_time(:second)

    :ets.insert(@table, {session_id, pane_id, now, nil, nil, :active})
    broadcast(session_id)
    :ok
  end

  @doc """
  Update the last activity timestamp for a session.
  """
  def touch(session_id, _source \\ :hook) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, pane_id, _last_hook_at, ended_at, ended_reason, status}] ->
        now = System.monotonic_time(:second)
        :ets.insert(@table, {session_id, pane_id, now, ended_at, ended_reason, status})
        :ok

      [] ->
        :ok
    end
  end

  @doc """
  Mark a session as ended.
  """
  def end_session(session_id, reason \\ nil) do
    now = System.monotonic_time(:second)

    case :ets.lookup(@table, session_id) do
      [{^session_id, pane_id, last_hook_at, _ended_at, _ended_reason, _status}] ->
        :ets.insert(@table, {session_id, pane_id, last_hook_at, now, reason, :ended})
        broadcast(session_id)
        :ok

      [] ->
        # Unknown session — insert as ended without crashing
        :ets.insert(@table, {session_id, nil, now, now, reason, :ended})
        broadcast(session_id)
        :ok
    end
  end

  @doc """
  Get the current status of a session.
  Returns a map with session info or nil if not tracked.
  """
  def status(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, pane_id, last_hook_at, ended_at, ended_reason, status}] ->
        %{
          session_id: session_id,
          status: resolve_status(status, last_hook_at, pane_id),
          last_activity_at: last_hook_at,
          pane_present: check_pane_present(pane_id),
          ended_reason: ended_reason,
          ended_at: ended_at
        }

      [] ->
        nil
    end
  end

  @doc """
  Get status for multiple sessions at once.
  Returns a map of session_id => status_map.
  """
  def status_map(session_ids) do
    Map.new(session_ids, fn session_id ->
      {session_id, status(session_id)}
    end)
  end

  # Server callbacks

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:second)

    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, _pane_id, last_hook_at, _ended_at, _ended_reason, status} ->
      if status != :ended and now - last_hook_at > @ttl_seconds do
        :ets.delete(@table, session_id)
        broadcast(session_id)
      end
    end)

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  # Private helpers

  defp resolve_status(:ended, _last_hook_at, _pane_id), do: :ended

  defp resolve_status(:active, last_hook_at, pane_id) do
    now = System.monotonic_time(:second)
    recent? = now - last_hook_at <= @ttl_seconds
    pane_present? = check_pane_present(pane_id)

    if recent? or pane_present?, do: :active, else: :inactive
  end

  defp check_pane_present(nil), do: false

  defp check_pane_present(pane_id) do
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Spotter.Services.Tmux.pane_exists?(pane_id)
  rescue
    _ -> false
  end

  defp broadcast(session_id) do
    info = status(session_id)

    payload =
      if info do
        info
      else
        %{
          session_id: session_id,
          status: :inactive,
          last_activity_at: nil,
          pane_present: false,
          ended_reason: nil
        }
      end

    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "session_activity",
      {:session_activity, payload}
    )
  end
end
