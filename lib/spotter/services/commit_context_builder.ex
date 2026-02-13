defmodule Spotter.Services.CommitContextBuilder do
  @moduledoc "Builds stable, merged context windows around changed code ranges."

  @default_context_lines 80

  @doc """
  Builds merged context windows from a list of changed ranges within a file.

  Each range is `{line_start, line_end}`. Windows are expanded by `context_lines`
  (default 80, env `SPOTTER_COMMIT_CONTEXT_LINES`), clamped to file bounds, and merged
  when overlapping.

  Returns a list of `%{line_start: integer, line_end: integer, content: String.t()}`.
  """
  @spec build_windows(String.t(), [{integer(), integer()}], keyword()) :: [map()]
  def build_windows(file_content, ranges, opts \\ []) do
    context_lines = Keyword.get(opts, :context_lines, context_lines_setting())
    all_lines = String.split(file_content, "\n")
    max_line = length(all_lines)

    ranges
    |> Enum.sort()
    |> Enum.map(fn {line_start, line_end} ->
      {max(1, line_start - context_lines), min(max_line, line_end + context_lines)}
    end)
    |> merge_overlapping()
    |> Enum.map(fn {ws, we} ->
      # Lines are 1-indexed
      content =
        all_lines
        |> Enum.slice((ws - 1)..(we - 1)//1)
        |> Enum.with_index(ws)
        |> Enum.map_join("\n", fn {line, num} -> "#{num}: #{line}" end)

      %{line_start: ws, line_end: we, content: content}
    end)
  end

  defp merge_overlapping([]), do: []

  defp merge_overlapping([first | rest]) do
    Enum.reduce(rest, [first], fn {s, e}, [{cs, ce} | acc] ->
      if s <= ce + 1 do
        [{cs, max(ce, e)} | acc]
      else
        [{s, e}, {cs, ce} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp context_lines_setting do
    case System.get_env("SPOTTER_COMMIT_CONTEXT_LINES") do
      nil -> @default_context_lines
      val -> String.to_integer(val)
    end
  end
end
