require "sqlite_vec"
require "active_record/connection_adapters/sqlite3_adapter"

module SqliteVecExtension
  def configure_connection
    super
    db = @raw_connection
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
  end
end

ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SqliteVecExtension)
