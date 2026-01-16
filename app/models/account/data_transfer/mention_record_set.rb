class Account::DataTransfer::MentionRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    created_at
    id
    mentionee_id
    mentioner_id
    source_id
    source_type
    updated_at
  ].freeze

  VALID_SOURCE_TYPES = %w[Card Comment].freeze

  private
    def records
      Mention.where(account: account)
    end

    def export_record(mention)
      zip.add_file "data/mentions/#{mention.id}.json", mention.as_json.to_json
    end

    def files
      zip.glob("data/mentions/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Mention.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Mention record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end

      unless VALID_SOURCE_TYPES.include?(data["source_type"])
        raise IntegrityError, "#{file_path} has invalid source_type: #{data['source_type']}"
      end
    end
end
