module Search::Record::SQLite
  extend ActiveSupport::Concern

  included do
    # Override the UUID id attribute from ApplicationRecord
    # FTS tables require integer rowids
    attribute :id, :integer, default: nil

    after_save :upsert_to_fts5_table
    after_destroy :delete_from_fts5_table
  end

  class_methods do
    def for_account(account_id)
      self
    end

    def matching_scope(query)
      joins("INNER JOIN search_records_fts ON search_records_fts.rowid = #{table_name}.id")
        .where("search_records_fts MATCH ?", query)
    end

    def search_scope(relation, query)
      opening_mark = connection.quote(Search::Highlighter::OPENING_MARK)
      closing_mark = connection.quote(Search::Highlighter::CLOSING_MARK)
      ellipsis = connection.quote(Search::Highlighter::ELIPSIS)

      relation.select(
        "#{table_name}.id",
        "#{table_name}.account_id",
        "#{table_name}.searchable_type",
        "#{table_name}.searchable_id",
        "#{table_name}.card_id",
        "#{table_name}.board_id",
        "#{table_name}.title",
        "#{table_name}.content",
        "#{table_name}.created_at",
        "highlight(search_records_fts, 0, #{opening_mark}, #{closing_mark}) AS highlighted_title",
        "highlight(search_records_fts, 1, #{opening_mark}, #{closing_mark}) AS highlighted_content",
        "snippet(search_records_fts, 1, #{opening_mark}, #{closing_mark}, #{ellipsis}, 20) AS content_snippet",
        "#{connection.quote(query.terms)} AS query"
      )
    end
  end

  def card_title
    if card_id
      if has_attribute?(:highlighted_title) && highlighted_title.present?
        highlighted_title.html_safe
      else
        card.title
      end
    end
  end

  def card_description
    if card_id && has_attribute?(:content_snippet) && content_snippet.present?
      content_snippet.html_safe
    end
  end

  def comment_body
    if comment && has_attribute?(:content_snippet) && content_snippet.present?
      content_snippet.html_safe
    end
  end

  private
    def upsert_to_fts5_table
      self.class.connection.execute(
        "INSERT OR REPLACE INTO search_records_fts(rowid, title, content) VALUES (#{id}, #{self.class.connection.quote(title)}, #{self.class.connection.quote(content)})"
      )
    end

    def delete_from_fts5_table
      self.class.connection.execute("DELETE FROM search_records_fts WHERE rowid = #{id}")
    end
end
