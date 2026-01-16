class Account::DataTransfer::ClosureRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    card_id
    created_at
    id
    updated_at
    user_id
  ].freeze

  private
    def records
      Closure.where(account: account)
    end

    def export_record(closure)
      zip.add_file "data/closures/#{closure.id}.json", closure.as_json.to_json
    end

    def files
      zip.glob("data/closures/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Closure.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Closure record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
