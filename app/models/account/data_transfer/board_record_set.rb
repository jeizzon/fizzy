class Account::DataTransfer::BoardRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    all_access
    created_at
    creator_id
    id
    name
    updated_at
  ].freeze

  private
    def records
      Board.where(account: account)
    end

    def export_record(board)
      zip.add_file "data/boards/#{board.id}.json", board.as_json.to_json
    end

    def files
      zip.glob("data/boards/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Board.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Board record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
