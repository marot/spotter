defmodule SpotterWeb.HooksController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Transcripts.Commit
  alias Spotter.Transcripts.FileSnapshot
  alias Spotter.Transcripts.Jobs.ComputeHeatmap
  alias Spotter.Transcripts.Jobs.EnrichCommits
  alias Spotter.Transcripts.Session
  alias Spotter.Transcripts.SessionCommitLink
  alias Spotter.Transcripts.Sessions
  alias Spotter.Transcripts.ToolCall

  require Ash.Query

  @max_commit_hashes 50
  @hash_pattern ~r/\A[0-9a-fA-F]{40}\z/

  def commit_event(conn, %{"session_id" => session_id, "new_commit_hashes" => hashes} = params)
      when is_binary(session_id) and is_list(hashes) do
    with :ok <- validate_hashes(hashes),
         {:ok, session} <- find_session(session_id) do
      evidence = build_evidence(params)
      ingested = ingest_commits(hashes, session, params["git_branch"], evidence)
      enqueue_enrichment(hashes, session)
      enqueue_heatmap(session)

      conn |> put_status(:created) |> json(%{ok: true, ingested: ingested})
    else
      {:error, :too_many} ->
        conn |> put_status(:bad_request) |> json(%{error: "too many commit hashes (max 50)"})

      {:error, :invalid_format} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid commit hash format"})

      {:error, :session_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})
    end
  end

  def commit_event(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "session_id and new_commit_hashes required"})
  end

  def file_snapshot(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    with {:ok, session} <- find_session(session_id),
         {:ok, attrs} <- build_attrs(params, session),
         {:ok, _snapshot} <- Ash.create(FileSnapshot, attrs) do
      enqueue_heatmap(session)

      conn
      |> put_status(:created)
      |> json(%{ok: true})
    else
      {:error, :session_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :invalid_params, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: reason})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset)})
    end
  end

  def file_snapshot(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})
  end

  def tool_call(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    case Sessions.find_or_create(session_id) do
      {:ok, session} ->
        error_content =
          case params["error_content"] do
            nil -> nil
            content when is_binary(content) -> String.slice(content, 0, 1000)
            _ -> nil
          end

        attrs = %{
          session_id: session.id,
          tool_use_id: params["tool_use_id"],
          tool_name: params["tool_name"],
          is_error: params["is_error"] || false,
          error_content: error_content
        }

        case Ash.create(ToolCall, attrs, action: :upsert) do
          {:ok, _tool_call} ->
            conn |> put_status(:created) |> json(%{ok: true})

          {:error, changeset} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset)})
        end

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def tool_call(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})
  end

  defp enqueue_heatmap(session) do
    %{project_id: session.project_id}
    |> ComputeHeatmap.new()
    |> Oban.insert()
  end

  defp enqueue_enrichment(hashes, session) when hashes != [] do
    %{
      commit_hashes: hashes,
      session_id: session.session_id,
      git_cwd: session.cwd || "."
    }
    |> EnrichCommits.new()
    |> Oban.insert()
  end

  defp enqueue_enrichment(_, _), do: :ok

  defp validate_hashes(hashes) do
    cond do
      length(hashes) > @max_commit_hashes -> {:error, :too_many}
      not Enum.all?(hashes, &Regex.match?(@hash_pattern, &1)) -> {:error, :invalid_format}
      true -> :ok
    end
  end

  defp build_evidence(params) do
    %{
      "tool_use_id" => params["tool_use_id"],
      "base_head" => params["base_head"],
      "head" => params["head"],
      "captured_at" => params["captured_at"],
      "source" => "hook-minimal"
    }
  end

  defp ingest_commits(hashes, session, git_branch, evidence) do
    Enum.count(hashes, fn hash ->
      with {:ok, commit} <- Ash.create(Commit, %{commit_hash: hash, git_branch: git_branch}),
           {:ok, _link} <-
             Ash.create(SessionCommitLink, %{
               session_id: session.id,
               commit_id: commit.id,
               link_type: :observed_in_session,
               confidence: 1.0,
               evidence: evidence
             }) do
        true
      else
        _ -> false
      end
    end)
  end

  defp find_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, nil} -> {:error, :session_not_found}
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:error, :session_not_found}
    end
  end

  defp build_attrs(params, session) do
    with {:ok, change_type} <- to_existing_atom(params["change_type"], "change_type"),
         {:ok, source} <- to_existing_atom(params["source"], "source"),
         {:ok, timestamp} <- parse_timestamp(params["timestamp"]) do
      {:ok,
       %{
         session_id: session.id,
         tool_use_id: params["tool_use_id"],
         file_path: params["file_path"],
         relative_path: params["relative_path"],
         content_before: params["content_before"],
         content_after: params["content_after"],
         change_type: change_type,
         source: source,
         timestamp: timestamp
       }}
    end
  end

  defp to_existing_atom(value, field) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_params, "invalid #{field}: #{value}"}
  end

  defp to_existing_atom(nil, field), do: {:error, :invalid_params, "#{field} is required"}

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:ok, DateTime.utc_now()}
    end
  end

  defp parse_timestamp(_), do: {:ok, DateTime.utc_now()}
end
