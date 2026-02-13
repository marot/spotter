defmodule Spotter.Transcripts.CommitFile do
  @moduledoc "Normalized file entry for a git commit, capturing path and change type."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "commit_files"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:commit_id, :relative_path, :change_type]
      upsert? true
      upsert_identity :unique_commit_file
      upsert_fields [:change_type]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false

    attribute :change_type, :atom do
      allow_nil? false
      default :modified
      constraints one_of: [:added, :modified, :deleted, :renamed]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? false
    end
  end

  identities do
    identity :unique_commit_file, [:commit_id, :relative_path]
  end
end
