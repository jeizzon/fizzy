class Account::DataTransfer::TaggingRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    card_id
    created_at
    id
    tag_id
    updated_at
  ].freeze

  private
    def records
      Tagging.where(account: account)
    end

    def export_record(tagging)
      zip.add_file "data/taggings/#{tagging.id}.json", tagging.as_json.to_json
    end

    def files
      zip.glob("data/taggings/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Tagging.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Tagging record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
