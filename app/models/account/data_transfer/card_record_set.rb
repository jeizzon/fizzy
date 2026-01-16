class Account::DataTransfer::CardRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    board_id
    column_id
    created_at
    creator_id
    due_on
    id
    last_active_at
    number
    status
    title
    updated_at
  ].freeze

  private
    def records
      Card.where(account: account)
    end

    def export_record(card)
      zip.add_file "data/cards/#{card.id}.json", card.as_json.to_json
    end

    def files
      zip.glob("data/cards/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Card.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Card record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
