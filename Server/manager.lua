local Logger = Package.Require("logger.lua")

local Manager = {
    _models = {},
    _database = nil,
    _engine = nil,
}

local function isInitialized()
    if Manager._database == nil then
        return false
    end

    if Manager._engine == nil then
        return false
    end

    return true
end

---Executes a query on the database.
---@param sql string The SQL query to execute.
---@vararg any The arguments to pass to the query.
---@return integer|string result The result of the query. (affected rows, error (if any))
function Manager._Execute(sql, ...)
    if not isInitialized() then
        error("The ORM manager is not initialized.")
    end

    Logger.debug("Executing query: " .. sql .. " with args: " .. table.concat({...}, ", "))

    return Manager._database:Execute(sql, ...)
end

---Executes a query on the database asynchronously.
---@param sql string The SQL query to execute.
---@param callback function The callback to call when the query is done.
---@vararg any The arguments to pass to the query.
function Manager._ExecuteAsync(sql, callback, ...)
    if not isInitialized() then
        error("The ORM manager is not initialized.")
    end

    Logger.debug("Executing query: " .. sql .. " with args: " .. table.concat({...}, ", "))

    Manager._database:ExecuteAsync(sql, callback, ...)
end

---Executes a query on the database.
---@param sql string The SQL query to execute.
---@vararg any The arguments to pass to the query.
---@return table|string result The result of the query. (rows fetched, error (if any)).
function Manager._Select(sql, ...)
    if not isInitialized() then
        error("The ORM manager is not initialized.")
    end

    Logger.debug("Executing query: " .. sql .. " with args: " .. table.concat({...}, ", "))

    return Manager._database:Select(sql, ...)
end

---Executes a query on the database asynchronously.
---@param sql string The SQL query to execute.
---@param callback function The callback to call when the query is done.
---@vararg any The arguments to pass to the query.
function Manager._SelectAsync(sql, callback, ...)
    if not isInitialized() then
        error("The ORM manager is not initialized.")
    end

    Logger.debug("Executing query: " .. sql .. " with args: " .. table.concat({...}, ", "))

    Manager._database:SelectAsync(sql, callback, ...)
end

---Returns the last inserted id.
function Manager._LastInsertId()
    if Manager._engine == DatabaseEngine.SQLite then
        return Manager._Select("SELECT last_insert_rowid() as id")[1].id
    elseif Manager._engine == DatabaseEngine.MySQL then
        return Manager._Select("SELECT LAST_INSERT_ID() as id")[1].id
    elseif Manager._engine == DatabaseEngine.PostgreSQL then
        return Manager._Select("SELECT lastval() as id")[1].id
    else
        error("Unsupported database engine: " .. tostring(Manager._engine))
    end
end

---Sets the debug mode of the logger to true.
function Manager.EnableDebug()
    Logger.enableDebug()
end

---Initializes the ORM manager.
function Manager.Initialize(connectionString, engine)
    if isInitialized() then
        Logger.warning("The ORM manager is already initialized.")
        return
    end

    Manager._database = Database(engine, connectionString)
    Manager._engine = engine

    Logger.debug("Pinging DB...")
    local res = Manager._Execute("SELECT 1")
    if res == nil then
        error("Failed to ping DB.")
    else
        Logger.debug("DB ping successful.")
    end
end

return Manager