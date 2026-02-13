defmodule Spotter.Services.GitCommitReader do
  @moduledoc "Reads recent commit metadata from a git repository."

  require Logger

  alias Spotter.Services.GitLogReader

  @default_limit 10

  @doc """
  Returns a list of recent commit maps for the given repo.

  Options:
    - `:limit` - max commits to return (default 10)
    - `:branch` - branch name (default: auto-detect)
  """
  @spec recent_commits(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def recent_commits(repo_path, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    case GitLogReader.resolve_branch(repo_path, Keyword.get(opts, :branch)) do
      {:ok, branch} ->
        parse_recent(repo_path, branch, limit)

      {:error, reason} ->
        Logger.warning("GitCommitReader: could not resolve branch for #{repo_path}: #{reason}")
        {:error, reason}
    end
  end

  defp parse_recent(repo_path, branch, limit) do
    format = "%H%n%P%n%s%n%b%n%an%n%ae%n%aI%n%cI%nCOMMIT_END"

    args = [
      "-C",
      repo_path,
      "log",
      "--format=#{format}",
      "-n",
      to_string(limit),
      branch,
      "--no-merges"
    ]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_output(output)}

      {error, _} ->
        Logger.warning("GitCommitReader: git log failed: #{String.slice(error, 0, 200)}")
        {:error, :git_log_failed}
    end
  end

  @doc false
  def parse_output(output) do
    output
    |> String.split("COMMIT_END", trim: true)
    |> Enum.flat_map(&parse_commit_block/1)
  end

  defp parse_commit_block(block) do
    lines =
      block
      |> String.split("\n")
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()

    case lines do
      [hash, parents, subject | rest] when byte_size(hash) == 40 ->
        {body, [author_name, author_email, authored_at_str, committed_at_str | _]} =
          split_body_and_trailer(rest)

        [
          %{
            commit_hash: hash,
            parent_hashes: String.split(parents, " ", trim: true),
            subject: subject,
            body: if(body == "", do: nil, else: body),
            author_name: author_name,
            author_email: author_email,
            authored_at: parse_iso8601(authored_at_str),
            committed_at: parse_iso8601(committed_at_str)
          }
        ]

      _ ->
        []
    end
  end

  defp split_body_and_trailer(lines) do
    # The last 4 lines are: author_name, author_email, authored_at, committed_at
    # Everything before that is the body
    total = length(lines)

    if total >= 4 do
      body_lines = Enum.take(lines, total - 4)
      trailer = Enum.drop(lines, total - 4)
      body = body_lines |> Enum.join("\n") |> String.trim()
      {body, trailer}
    else
      {"", lines}
    end
  end

  defp parse_iso8601(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
