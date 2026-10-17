Package.Require("init.lua")
for _, name in ipairs({ "Index", "Embed", "Sti" }) do
  local module = dofile(NEBRA_OUT .. "/Server/" .. name .. ".lua")
  local database = name .. ".db"
  os.remove(database)
  module.run(NanosORM.connect(DatabaseEngine.SQLite, database), check, database)
end
