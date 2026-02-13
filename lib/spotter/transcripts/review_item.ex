defmodule Spotter.Transcripts.ReviewItem do
  @moduledoc "Spaced-repetition review item for commit messages and code hotspots."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "review_items"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :target_kind,
        :importance,
        :next_due_on,
        :interval_days,
        :project_id,
        :commit_id,
        :commit_hotspot_id,
        :flashcard_id
      ]

      upsert? true
      upsert_identity :unique_review_item
    end

    update :update do
      primary? true

      accept [
        :importance,
        :next_due_on,
        :interval_days,
        :seen_count,
        :last_seen_at,
        :suspended_at
      ]
    end

    update :mark_seen do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        now = DateTime.utc_now()
        item = changeset.data
        new_count = (item.seen_count || 0) + 1

        changeset
        |> Ash.Changeset.force_change_attribute(:seen_count, new_count)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, now)
      end
    end
  end

  validations do
    validate fn changeset, _context ->
               target_kind = Ash.Changeset.get_attribute(changeset, :target_kind)
               commit_id = Ash.Changeset.get_attribute(changeset, :commit_id)
               hotspot_id = Ash.Changeset.get_attribute(changeset, :commit_hotspot_id)

               flashcard_id = Ash.Changeset.get_attribute(changeset, :flashcard_id)

               case target_kind do
                 :commit_message when is_nil(commit_id) ->
                   {:error,
                    field: :commit_id, message: "is required when target_kind is commit_message"}

                 :commit_message when not is_nil(hotspot_id) ->
                   {:error,
                    field: :commit_hotspot_id,
                    message: "must be nil when target_kind is commit_message"}

                 :commit_hotspot when is_nil(hotspot_id) ->
                   {:error,
                    field: :commit_hotspot_id,
                    message: "is required when target_kind is commit_hotspot"}

                 :flashcard when is_nil(flashcard_id) ->
                   {:error,
                    field: :flashcard_id, message: "is required when target_kind is flashcard"}

                 :flashcard when not is_nil(commit_id) ->
                   {:error,
                    field: :commit_id, message: "must be nil when target_kind is flashcard"}

                 :flashcard when not is_nil(hotspot_id) ->
                   {:error,
                    field: :commit_hotspot_id,
                    message: "must be nil when target_kind is flashcard"}

                 _ ->
                   :ok
               end
             end,
             on: [:create]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :target_kind, :atom do
      allow_nil? false
      constraints one_of: [:commit_message, :commit_hotspot, :flashcard]
    end

    attribute :importance, :atom do
      allow_nil? false
      default :medium
      constraints one_of: [:low, :medium, :high]
    end

    attribute :next_due_on, :date
    attribute :interval_days, :integer

    attribute :seen_count, :integer do
      allow_nil? false
      default 0
    end

    attribute :last_seen_at, :utc_datetime_usec
    attribute :suspended_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? true
    end

    belongs_to :commit_hotspot, Spotter.Transcripts.CommitHotspot do
      allow_nil? true
    end

    belongs_to :flashcard, Spotter.Transcripts.Flashcard do
      allow_nil? true
    end
  end

  identities do
    identity :unique_review_item, [
      :project_id,
      :target_kind,
      :commit_id,
      :commit_hotspot_id,
      :flashcard_id
    ]
  end
end
