class Account::DataTransfer::AccessRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    accessed_at
    account_id
    board_id
    created_at
    id
    involvement
    updated_at
    user_id
  ].freeze

  private
    def records
      Access.where(account: account)
    end

    def export_record(access)
      zip.add_file "data/accesses/#{access.id}.json", access.as_json.to_json
    end

    def files
      zip.glob("data/accesses/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Access.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Access record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
