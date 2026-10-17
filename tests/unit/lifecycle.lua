Package.Require("init.lua")
local ORM = NanosORM
local function sync(fn)
  local results
  fn(function(...) results = table.pack(...) end)
  if results == nil then return nil end
  return table.unpack(results, 1, results.n)
end
local function raw(sql)
  local p = io.popen("sqlite3 life.db \"" .. sql .. "\" 2>&1")
  local out = p:read("a"):gsub("%s+$", "")
  p:close()
  return out
end

local Author = ORM.entity("Author")
  :column("id", "integer"):id()
  :column("name", "string")
  :oneToMany("books", "Book", "author"):cascade("persist"):orphanRemoval()
  :oneToOne("profile", "Profile"):cascade("persist"):orphanRemoval():nullable()
  :build()
local Book = ORM.entity("Book")
  :column("id", "integer"):id()
  :column("title", "string")
  :manyToOne("author", "Author"):nullable()
  :build()
local Profile = ORM.entity("Profile")
  :column("id", "integer"):id()
  :column("bio", "string")
  :build()

os.remove("life.db")
local em = ORM.connect(DatabaseEngine.SQLite, "life.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)

local function mapSize()
  local n = 0
  for _, entities in pairs(em._loader._identityMap) do for _ in pairs(entities) do n = n + 1 end end
  return n
end

print("-- weak identity map")
do
  for i = 1, 3 do
    local a = Author.new()
    a.name = "a" .. i
    em:persist(a)
  end
end
check("flush", sync(function(cb) em:flush(cb) end), true)
collectgarbage() collectgarbage()
check("clean unreferenced entities collected", mapSize(), 0)
local all = sync(function(cb) em:getRepository(Author):findAll(cb) end)
check("loaded", #all, 3)
check("map holds referenced", mapSize(), 3)
all[1].name = "changed"
all = nil
collectgarbage() collectgarbage()
check("dirty entity pinned", mapSize(), 1)
check("flush dirty", sync(function(cb) em:flush(cb) end), true)
check("db updated", raw("select name from author where id = 1"), "changed")
collectgarbage() collectgarbage()
check("unpinned after flush", mapSize(), 0)

local a2 = sync(function(cb) em:find(Author, 2, cb) end)
local books = a2.books
local b = Book.new()
b.title = "t"
b.author = a2
books:add(b)
em:persist(b)
check("flush book", sync(function(cb) em:flush(cb) end), true)
local bookId = b.id
a2, b, books = nil, nil, nil
collectgarbage() collectgarbage()
check("all collected again", mapSize(), 0)

print("-- orphanRemoval one-to-many")
local a3 = sync(function(cb) em:find(Author, 2, cb) end)
local bs = a3.books
sync(function(cb) em:load(a3, { "books" }, cb) end)
check("book loaded", bs:size(), 1)
local removedBook = bs:get(1)
bs:remove(removedBook)
removedBook = nil
a3 = nil
collectgarbage() collectgarbage()
check("owner pinned by orphan", mapSize() >= 1, true)
check("flush orphan", sync(function(cb) em:flush(cb) end), true)
check("orphan deleted", raw("select count(*) from book"), "0")
bs = nil

print("-- moving a child is not an orphan")
local x = sync(function(cb) em:find(Author, 1, cb) end)
local y = sync(function(cb) em:find(Author, 3, cb) end)
local mb = Book.new() mb.title = "m"
x.books:add(mb)
check("flush move setup", sync(function(cb) em:flush(cb) end), true)
sync(function(cb) em:load({ x, y }, { "books" }, cb) end)
x.books:remove(mb)
y.books:add(mb)
check("flush move", sync(function(cb) em:flush(cb) end), true)
check("moved book kept", raw("select author_id from book where title = 'm'"), "3")

print("-- orphanRemoval one-to-one")
local p1 = Profile.new() p1.bio = "first"
x.profile = p1
check("flush profile", sync(function(cb) em:flush(cb) end), true)
check("profile stored", raw("select count(*) from profile"), "1")
local p2 = Profile.new() p2.bio = "second"
x.profile = p2
check("flush replace", sync(function(cb) em:flush(cb) end), true)
check("old profile removed", raw("select group_concat(bio) from profile"), "second")
x.profile = nil
check("flush unset", sync(function(cb) em:flush(cb) end), true)
check("profile removed on nil", raw("select count(*) from profile"), "0")

print("-- transactional on the same EntityManager")
local work
check("transactional commit", sync(function(cb) em:transactional(function(tx, done) work = tx local a = Author.new() a.name = "wrapped" tx:persist(a) done(true) end, cb) end), true)
check("work receives the same em", work == em, true)
check("wrapped stored", raw("select count(*) from author where name = 'wrapped'"), "1")
local stale = sync(function(cb) em:find(Author, 1, cb) end)
check("em sees changes made in transaction", sync(function(cb) em:transactional(function(tx, done) local a = sync(function(c) tx:find(Author, 1, c) end) a.name = "renamed" done(true) end, cb) end), true)
check("same entity updated", stale.name, "renamed")

print("-- transaction timeout")
Timers = {}
local result
em:transactional(function(tx, done)
  local a = Author.new() a.name = "never"
  tx:persist(a)
end, { timeout = 5 }, function(ok, err) result = { ok, err } end)
check("timer scheduled", #Timers > 0 and Timers[#Timers].ms, 5000)
check("not finished yet", result, nil)
check("em in transaction", em:isTransactionActive(), true)
fireTimers()
check("rolled back", result and result[1], false)
check("timeout message", result and result[2], "The transaction timed out after 5 seconds")
check("nothing written", raw("select count(*) from author where name = 'never'"), "0")
check("em usable after timeout", sync(function(cb) em:getRepository(Author):count(nil, cb) end) >= 3, true)
check("no transaction left", em:isTransactionActive(), false)

Timers = {}
local okResult
em:transactional(function(tx, done) local a = Author.new() a.name = "fast" tx:persist(a) done(true) end, { timeout = 5 }, function(ok) okResult = ok end)
check("fast tx ok", okResult, true)
check("timer cleared", Timers[1] and Timers[1].cleared, true)

print("-- beginTransaction / commit / rollback")
local tx = sync(function(cb) em:beginTransaction(cb) end)
check("tx active", tx:isActive() and em:isTransactionActive(), true)
local t1 = Author.new() t1.name = "committed"
em:persist(t1)
check("commit", sync(function(cb) tx:commit(cb) end), true)
check("deferred rollback after commit is no-op", sync(function(cb) tx:rollback(cb) end), true)
check("committed row", raw("select count(*) from author where name = 'committed'"), "1")
check("tx inactive", tx:isActive(), false)
check("second commit fails", sync(function(cb) tx:commit(cb) end), false)
check("t1 still managed", em:contains(t1), true)

local tx2 = sync(function(cb) em:beginTransaction(cb) end)
local t2 = Author.new() t2.name = "rolled"
em:persist(t2)
check("flush inside", sync(function(cb) em:flush(cb) end), true)
check("visible inside", raw("select count(*) from author where name = 'rolled'"), "0")
check("rollback", sync(function(cb) tx2:rollback(cb) end), true)
check("rolled back row", sync(function(cb) em:getRepository(Author):count({ name = "rolled" }, cb) end), 0)
check("untouched entity stays managed after rollback", em:contains(t1), true)
check("entity written in rolled back transaction detached", em:contains(t2), false)

print("-- rollback only detaches what the transaction wrote")
local keeper = Author.new() keeper.name = "keeper"
local untouched = Author.new() untouched.name = "untouched"
local parent = Author.new() parent.name = "parent"
parent.books = {}
em:persist(keeper) em:persist(untouched) em:persist(parent)
check("setup keeper", sync(function(cb) em:flush(cb) end), true)
local tx5 = sync(function(cb) em:beginTransaction(cb) end)
local child = Book.new() child.title = "child" child.author = parent
parent.books:add(child)
keeper.name = "keeper changed"
em:persist(child)
check("flush child inside", sync(function(cb) em:flush(cb) end), true)
check("rollback child", sync(function(cb) tx5:rollback(cb) end), true)
check("untouched stays managed", em:contains(untouched), true)
check("changed and flushed keeper detached", em:contains(keeper), false)
check("child detached", em:contains(child), false)
check("parent of written child detached", em:contains(parent), false)
check("child not stored", raw("select count(*) from book where title = 'child'"), "0")
check("keeper change rolled back in db", raw("select name from author where id = " .. keeper.id), "keeper")
local reloaded = sync(function(cb) em:find(Author, parent.id, cb) end)
check("parent reloads fresh", reloaded ~= parent and reloaded ~= nil, true)
check("flush after rollback writes nothing stale", sync(function(cb) em:flush(cb) end), true)
check("still no child", raw("select count(*) from book where title = 'child'"), "0")

print("-- nesting")
local outer = sync(function(cb) em:beginTransaction(cb) end)
local inner = sync(function(cb) em:beginTransaction(cb) end)
check("nesting level", em:getTransactionNestingLevel(), 2)
check("wrong order rejected", sync(function(cb) outer:commit(cb) end), false)
local n1 = Author.new() n1.name = "nested"
em:persist(n1)
check("inner commit", sync(function(cb) inner:commit(cb) end), true)
check("level back to 1", em:getTransactionNestingLevel(), 1)
check("outer commit", sync(function(cb) outer:commit(cb) end), true)
check("nested committed", raw("select count(*) from author where name = 'nested'"), "1")

local outer2 = sync(function(cb) em:beginTransaction(cb) end)
local inner2 = sync(function(cb) em:beginTransaction(cb) end)
local n2 = Author.new() n2.name = "nested2"
em:persist(n2)
check("inner rollback", sync(function(cb) inner2:rollback(cb) end), true)
check("rollback only", em:isRollbackOnly(), true)
local okOuter, errOuter = sync(function(cb) outer2:commit(cb) end)
check("outer commit fails", okOuter, false)
print("   " .. tostring(errOuter))
check("nested2 not written", raw("select count(*) from author where name = 'nested2'"), "0")
check("outer deferred rollback no-op", sync(function(cb) outer2:rollback(cb) end), true)

local nestedResult
em:transactional(function(a, done)
  em:transactional(function(b, innerDone)
    local x = Author.new() x.name = "nested-wrap"
    b:persist(x)
    innerDone(true)
  end, function(ok) nestedResult = ok end)
  done(true)
end, function(ok) nestedResult = nestedResult and ok end)
check("nested transactional", nestedResult, true)
check("nested-wrap stored", raw("select count(*) from author where name = 'nested-wrap'"), "1")

local tx3 = sync(function(cb) em:beginTransaction(cb) end)
local bad = Book.new() bad.title = nil
em:persist(bad)
local ok3, err3 = sync(function(cb) tx3:commit(cb) end)
check("failing commit", ok3, false)
check("auto rolled back on failed commit", em:isTransactionActive(), false)
check("rollback after failed commit no-op", sync(function(cb) tx3:rollback(cb) end), true)

Timers = {}
local tx4 = sync(function(cb) em:beginTransaction({ timeout = 2 }, cb) end)
fireTimers()
check("timeout ends begin tx", tx4:isActive(), false)
check("commit after timeout reports it", select(2, sync(function(cb) tx4:commit(cb) end)), "The transaction timed out after 2 seconds")
