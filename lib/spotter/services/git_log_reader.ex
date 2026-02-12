defmodule Spotter.Services.GitLogReader do
  @moduledoc "Thin wrapper around git CLI to read commit history with changed files."

  require Logger

  @doc """
  Returns a list of maps with :hash, :timestamp, and :files for each commit
  on the given branch within the time window.

  Options:
    - :since_days - number of days to look back (default 30)
    - :branch - branch name (default: auto-detect)
  """
  @spec changed_files_by_commit(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def changed_files_by_commit(repo_path, opts \\ []) do
    since_days = Keyword.get(opts, :since_days, 30)

    case resolve_branch(repo_path, Keyword.get(opts, :branch)) do
      {:ok, branch} ->
        parse_log(repo_path, branch, since_days)

      {:error, reason} ->
        Logger.warning("GitLogReader: could not resolve branch for #{repo_path}: #{reason}")
        {:error, reason}
    end
  end

  @doc "Auto-detect the default branch for a repo."
  @spec resolve_branch(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def resolve_branch(_repo_path, branch) when is_binary(branch) and branch != "",
    do: {:ok, branch}

  def resolve_branch(repo_path, _) do
    case System.cmd("git", ["-C", repo_path, "symbolic-ref", "refs/remotes/origin/HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, output |> String.trim() |> String.replace("refs/remotes/origin/", "")}

      _ ->
        detect_fallback_branch(repo_path)
    end
  end

  defp detect_fallback_branch(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-parse", "--verify", "main"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        {:ok, "main"}

      _ ->
        case System.cmd("git", ["-C", repo_path, "rev-parse", "--verify", "master"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, "master"}
          _ -> {:error, :no_default_branch}
        end
    end
  end

  defp parse_log(repo_path, branch, since_days) do
    args = [
      "-C",
      repo_path,
      "log",
      "--name-only",
      "--format=COMMIT:%H:%ct",
      "--since=#{since_days} days ago",
      branch,
      "--no-merges"
    ]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_output(output)}

      {error, _} ->
        Logger.warning("GitLogReader: git log failed: #{String.slice(error, 0, 200)}")
        {:error, :git_log_failed}
    end
  end

  @doc false
  def parse_output(output) do
    output
    |> String.split("COMMIT:", trim: true)
    |> Enum.flat_map(&parse_commit_block/1)
  end

  defp parse_commit_block(block) do
    lines = String.split(block, "\n", trim: true)

    case lines do
      [header | file_lines] ->
        case String.split(header, ":", parts: 2) do
          [hash, unix_str] ->
            timestamp = parse_unix_timestamp(unix_str)
            files = Enum.reject(file_lines, &(&1 == ""))

            [%{hash: hash, timestamp: timestamp, files: files}]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  defp parse_unix_timestamp(str) do
    case Integer.parse(str) do
      {unix, _} -> DateTime.from_unix!(unix)
      :error -> DateTime.utc_now()
    end
  end
end
