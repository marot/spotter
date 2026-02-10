defmodule Spotter.Services.TmuxOutput do
  @moduledoc """
  Parses and transforms tmux control mode output for xterm.js rendering.
  """

  @doc """
  Parses a tmux control mode line into a tagged tuple.

  ## Examples

      iex> Spotter.Services.TmuxOutput.parse_control_line("%output %5 hello\\\\040world")
      {:output, "%5", "hello\\\\040world"}

      iex> Spotter.Services.TmuxOutput.parse_control_line("%begin 123")
      :begin

      iex> Spotter.Services.TmuxOutput.parse_control_line("%end 123")
      :end

      iex> Spotter.Services.TmuxOutput.parse_control_line("%exit")
      :exit
  """
  def parse_control_line(line) do
    case String.split(line, " ", parts: 3) do
      ["%output", pane, content] -> {:output, pane, content}
      ["%begin" | _] -> :begin
      ["%end" | _] -> :end
      ["%exit" | _] -> :exit
      _ -> :unknown
    end
  end

  @doc """
  Splits data into complete lines and a remaining partial line.

  Returns `{complete_lines, remaining}`.

  ## Examples

      iex> Spotter.Services.TmuxOutput.split_complete_lines("line1\\nline2\\npartial")
      {["line1", "line2"], "partial"}

      iex> Spotter.Services.TmuxOutput.split_complete_lines("no newline")
      {[], "no newline"}

      iex> Spotter.Services.TmuxOutput.split_complete_lines("complete\\n")
      {["complete"], ""}
  """
  def split_complete_lines(data) do
    case String.split(data, "\n", trim: false) do
      [only] -> {[], only}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  @doc """
  Decodes tmux control mode octal escapes and fixes UTF-8 encoding.

  ## Examples

      iex> Spotter.Services.TmuxOutput.decode_output("hello\\\\040world")
      "hello world"

      iex> Spotter.Services.TmuxOutput.decode_output("no escapes")
      "no escapes"
  """
  def decode_output(str) do
    decoded = decode_octal(str)

    if String.valid?(decoded),
      do: decoded,
      else: :unicode.characters_to_binary(decoded, :latin1, :utf8)
  end

  @doc """
  Prepares tmux capture-pane output for xterm.js rendering.

  Applies two transforms:
  - Strips trailing spaces (tmux pads lines to pane width)
  - Converts `\\n` to `\\r\\n` (xterm.js needs carriage return for column reset)

  ## Examples

      iex> Spotter.Services.TmuxOutput.prepare_for_xterm("hello   \\nworld   \\n")
      "hello\\r\\nworld\\r\\n"

      iex> Spotter.Services.TmuxOutput.prepare_for_xterm("already\\r\\nhas cr")
      "already\\r\\nhas cr"
  """
  def prepare_for_xterm(content) do
    content
    |> strip_trailing_spaces()
    |> normalize_newlines()
  end

  @doc """
  Strips trailing spaces from each line.

  tmux `capture-pane` pads lines to the full pane width with spaces.
  This causes incorrect wrapping when rendered in a narrower terminal.

  ## Examples

      iex> Spotter.Services.TmuxOutput.strip_trailing_spaces("hello   \\nworld   \\n")
      "hello\\nworld\\n"

      iex> Spotter.Services.TmuxOutput.strip_trailing_spaces("  leading preserved   ")
      "  leading preserved"
  """
  def strip_trailing_spaces(content) do
    content
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
  end

  @doc false
  def decode_octal(str) do
    Regex.replace(~r/\\(\d{3})/, str, fn _, octal ->
      <<String.to_integer(octal, 8)>>
    end)
  end

  defp normalize_newlines(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\n", "\r\n")
  end
end
