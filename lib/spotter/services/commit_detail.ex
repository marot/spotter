defmodule Spotter.Services.CommitDetail do
  @moduledoc "Data service for the commit detail page."

  alias Spotter.Transcripts.{
    CoChangeGroup,
    Commit,
    Message,
    Session,
    SessionCommitLink
  }

  require Ash.Query

  @doc """
  Loads a commit by its database ID.

  Returns `{:ok, commit}` or `{:error, :not_found}`.
  """
  def load_commit(commit_id) do
    case Ash.get(Commit, commit_id) do
      {:ok, commit} -> {:ok, commit}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Loads sessions linked to a commit, sorted by confidence desc then started_at desc.
  """
  def load_linked_sessions(commit_id) do
    links =
      SessionCommitLink
      |> Ash.Query.filter(commit_id == ^commit_id)
      |> Ash.Query.sort(confidence: :desc, inserted_at: :desc)
      |> Ash.read!()

    session_ids = Enum.map(links, & &1.session_id) |> Enum.uniq()

    sessions_by_id =
      if session_ids == [] do
        %{}
      else
        Session
        |> Ash.Query.filter(id in ^session_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      end

    links_by_session = Enum.group_by(links, & &1.session_id)

    session_ids
    |> Enum.map(fn sid ->
      session = Map.get(sessions_by_id, sid)
      session_links = Map.get(links_by_session, sid, [])

      if session do
        %{
          session: session,
          link_types: session_links |> Enum.map(& &1.link_type) |> Enum.uniq(),
          max_confidence: session_links |> Enum.map(& &1.confidence) |> Enum.max(fn -> 0.0 end)
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{-&1.max_confidence, &1.session.started_at || &1.session.inserted_at}, :asc)
  end

  @doc """
  Loads co-change groups that overlap with the commit's changed files.
  """
  def load_co_change_overlaps(commit) do
    changed = commit.changed_files || []

    if changed == [] do
      []
    else
      changed_set = MapSet.new(changed)

      CoChangeGroup
      |> Ash.Query.filter(scope == :file)
      |> Ash.read!()
      |> Enum.filter(fn group ->
        group.members
        |> Enum.any?(&MapSet.member?(changed_set, &1))
      end)
      |> Enum.sort_by(& &1.frequency_30d, :desc)
    end
  end

  @doc """
  Loads messages for a given session (for transcript display).
  """
  def load_session_messages(session_id) do
    Message
    |> Ash.Query.filter(session_id == ^session_id and is_nil(subagent_id))
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.read!()
    |> Enum.map(fn msg ->
      %{
        id: msg.id,
        uuid: msg.uuid,
        type: msg.type,
        role: msg.role,
        content: msg.content,
        raw_payload: msg.raw_payload,
        timestamp: msg.timestamp,
        agent_id: msg.agent_id
      }
    end)
  end

  @doc """
  Fetches the diff text for a commit using git. Falls back to a placeholder.
  """
  def fetch_diff(commit, sessions) do
    cwd = find_usable_cwd(sessions)

    if cwd do
      case System.cmd(
             "git",
             ["show", "--patch", "--format=", commit.commit_hash],
             cd: cwd,
             stderr_to_stdout: true
           ) do
        {output, 0} when byte_size(output) > 0 -> output
        _ -> "Diff not available."
      end
    else
      "No session working directory available to fetch diff."
    end
  end

  defp find_usable_cwd(sessions) do
    sessions
    |> Enum.map(& &1.session.cwd)
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.dir?/1)
  end
end
