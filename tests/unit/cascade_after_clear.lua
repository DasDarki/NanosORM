Package.Require("init.lua")
local ORM = NanosORM
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local Author = ORM.entity("Author"):column("id", "integer"):id():column("name", "string"):oneToMany("books", "Book", "author"):cascade("persist"):build()
local Book = ORM.entity("Book"):column("id", "integer"):id():column("title", "string"):manyToOne("author", "Author"):nullable():build()
for _, mode in ipairs({ "none", "clear", "rollback", "timeout" }) do
  os.remove("repro.db")
  local em = ORM.connect(DatabaseEngine.SQLite, "repro.db")
  sync(function(cb) em:createSchema(cb) end)
  local a = Author.new() a.name = "x" em:persist(a) sync(function(cb) em:flush(cb) end)
  if mode == "timeout" then
    Timers = {}
    local tx = sync(function(cb) em:beginTransaction({ timeout = 1 }, cb) end)
    fireTimers()
  elseif mode == "rollback" then
    local tx = sync(function(cb) em:beginTransaction(cb) end)
    sync(function(cb) tx:rollback(cb) end)
  elseif mode == "clear" then
    em:clear()
  end
  local h = sync(function(cb) em:getRepository(Author):findOneBy({ name = "x" }, cb) end)
  local b = Book.new() b.title = "t" b.author = h
  h.books:add(b)
  check(mode .. ": cascade persist into unloaded collection", sync(function(cb) em:flush(cb) end) and em:contains(b), true)
end
