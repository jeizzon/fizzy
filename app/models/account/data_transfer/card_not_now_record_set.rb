class Account::DataTransfer::CardNotNowRecordSet < Account::DataTransfer::RecordSet
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
      Card::NotNow.where(account: account)
    end

    def export_record(not_now)
      zip.add_file "data/card_not_nows/#{not_now.id}.json", not_now.as_json.to_json
    end

    def files
      zip.glob("data/card_not_nows/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Card::NotNow.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "CardNotNow record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
