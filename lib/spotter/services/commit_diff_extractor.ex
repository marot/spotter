defmodule Spotter.Services.CommitDiffExtractor do
  @moduledoc "Extracts diff statistics for a commit using git diff-tree --numstat."

  require Logger

  @doc """
  Returns diff stats for a commit.

  Returns `{:ok, stats}` where stats is a map with:
    - `:files_changed` - total number of files changed
    - `:insertions` - total lines added
    - `:deletions` - total lines deleted
    - `:binary_files` - list of paths that are binary
    - `:file_stats` - list of per-file stats
  """
  @spec diff_stats(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def diff_stats(repo_path, commit_hash) do
    args = ["-C", repo_path, "diff-tree", "--numstat", "-r", commit_hash]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_numstat(output)}

      {error, _} ->
        Logger.warning(
          "CommitDiffExtractor: git diff-tree failed: #{String.slice(error, 0, 200)}"
        )

        {:error, :git_diff_tree_failed}
    end
  end

  @doc false
  def parse_numstat(output) do
    rows =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_numstat_row/1)

    binary_files = for %{binary?: true, path: path} <- rows, do: path
    text_rows = Enum.reject(rows, & &1.binary?)

    %{
      files_changed: length(rows),
      insertions: text_rows |> Enum.map(& &1.added) |> Enum.sum(),
      deletions: text_rows |> Enum.map(& &1.deleted) |> Enum.sum(),
      binary_files: binary_files,
      file_stats: rows
    }
  end

  defp parse_numstat_row(line) do
    case String.split(line, "\t", parts: 3) do
      ["-", "-", path] ->
        [%{path: path, added: 0, deleted: 0, binary?: true}]

      [added_str, deleted_str, path] ->
        with {added, ""} <- Integer.parse(added_str),
             {deleted, ""} <- Integer.parse(deleted_str) do
          [%{path: path, added: added, deleted: deleted, binary?: false}]
        else
          _ -> []
        end

      _ ->
        []
    end
  end
end
