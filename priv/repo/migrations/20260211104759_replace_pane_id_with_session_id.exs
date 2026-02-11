defmodule Spotter.Repo.Migrations.ReplacePaneIdWithSessionId do
  @moduledoc """
  Replaces pane_id with session_id on annotations.

  SQLite cannot alter column types or add FKs, so we recreate the table.
  Existing annotation data is intentionally dropped (clean slate per epic spec).
  """

  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS annotations")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      selected_text TEXT NOT NULL,
      start_row INTEGER NOT NULL,
      start_col INTEGER NOT NULL,
      end_row INTEGER NOT NULL,
      end_col INTEGER NOT NULL,
      comment TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("CREATE INDEX annotations_session_id_index ON annotations(session_id)")
  end

  def down do
    execute("DROP TABLE IF EXISTS annotations")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      pane_id TEXT NOT NULL,
      selected_text TEXT NOT NULL,
      start_row INTEGER NOT NULL,
      start_col INTEGER NOT NULL,
      end_row INTEGER NOT NULL,
      end_col INTEGER NOT NULL,
      comment TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)
  end
end
