local Logger = Package.Require("logger.lua")
local Manager = Package.Require("manager.lua")

local function simple_sql_escape(value)
    if type(value) == "string" then
        return "'" .. value:gsub("'", "\\'") .. "'"
    end

    return tostring(value)
end

---Gets the schema of a table in the SQLite database.
---@param tableName string The name of the table to get the schema from.
---@return table|false schema The schema of the table. False if the table does not exist or an error occured.
local function getSqliteTableSchema(tableName)
    local schemaBasic = Manager._Select("PRAGMA table_info(" .. tableName .. ")")
    
    if not schemaBasic or #schemaBasic == 0 then
        return false
    end
    
    local foreignKeys = Manager._Select("PRAGMA foreign_key_list(" .. tableName .. ")")
    
    local indices = Manager._Select("PRAGMA index_list(" .. tableName .. ")")
    local uniqueIndices = {}

    for _, index in ipairs(indices or {}) do
        if index.unique == "1" then
            local indexInfo = Manager._Select("PRAGMA index_info(" .. index.name .. ")")
            for _, col in ipairs(indexInfo) do
                uniqueIndices[col.name] = true
            end
        end
    end

    local processedSchema = {}
    for _, column in ipairs(schemaBasic) do
        local foreignKey = nil
        for _, fk in ipairs(foreignKeys or {}) do
            if fk.from == column.name then
                foreignKey = {
                    table = fk.table,
                    column = fk.to,
                    onUpdate = fk.on_update,
                    onDelete = fk.on_delete
                }
                break
            end
        end

        processedSchema[column.name] = processedSchema[column.name] or {
            index = column.cid,
            name = column.name,
            type = DataTypes:GetTypeByDatabaseType(DatabaseEngine.SQLite, column.type),
            isNotNull = column.notnull == "1",
            defaultValue = column.dflt_value,
            isPrimaryKey = column.pk == "1",
            isUnique = uniqueIndices[column.name] or false,
            isAutoIncrement = (column.pk == "1" and column.type == "INTEGER"),
            foreignKey = foreignKey,
        }
    end
    
    return processedSchema
end

local function generateCreateTableQuery(engine, tableName, modelColumns)
    local columns = {}
    local foreignKeys = {}

    for _, column in pairs(modelColumns) do
        local colSql = column.name .. " " .. DataTypes:GetDatabaseType(engine, column.type)
        if column.isNotNull then
            colSql = colSql .. " NOT NULL"
        end

        if column.defaultValue ~= nil then
            colSql = colSql .. " DEFAULT " .. simple_sql_escape(column.defaultValue)
        end

        if column.isPrimaryKey then
            colSql = colSql .. " PRIMARY KEY"

            if column.isAutoIncrement and engine ~= DatabaseEngine.SQLite then
                colSql = colSql .. " AUTOINCREMENT"
            end
        end

        if column.isUnique then
            colSql = colSql .. " UNIQUE"
        end

        table.insert(columns, colSql)

        if column.foreignKey then
            table.insert(foreignKeys, "FOREIGN KEY (" .. column.name .. ") REFERENCES " .. column.foreignKey.table .. "(" .. column.foreignKey.column .. ")" .. (column.foreignKey.onUpdate and " ON UPDATE " .. column.foreignKey.onUpdate or "") .. (column.foreignKey.onDelete and " ON DELETE " .. column.foreignKey.onDelete or ""))
        end
    end

    return "CREATE TABLE IF NOT EXISTS " .. tableName .. " (" .. table.concat(columns, ", ") .. (#foreignKeys > 0 and ", " .. table.concat(foreignKeys, ", ") or "") .. ")"
end

local function generateAlterQueries(engine, tableName, currentColumns, modelColumns, withDrops)
    local queries = {}

    for _, column in pairs(modelColumns) do
        local currentColumn = nil
        for _, c in pairs(currentColumns) do
            if c.name == column.name then
                currentColumn = c
                break
            end
        end

        if currentColumn == nil then
            table.insert(queries, "ADD COLUMN " .. column.name .. " " .. DataTypes:GetDatabaseType(engine, column.type) .. (column.isNotNull and " NOT NULL" or "") .. (column.defaultValue and " DEFAULT " .. simple_sql_escape(column.defaultValue or "")) .. (column.isPrimaryKey and " PRIMARY KEY" or "") .. (column.isAutoIncrement and " AUTOINCREMENT" or "") .. (column.isUnique and " UNIQUE" or ""))
        else
            -- CURRENTLY NOT SUPPORTED
            --[[if currentColumn.type ~= column.type then
                table.insert(queries, "ALTER COLUMN " .. column.name .. " TYPE " .. DataTypes:GetDatabaseType(engine, column.type))
            end]]--

            if currentColumn.isNotNull ~= column.isNotNull then
                table.insert(queries, "ALTER COLUMN " .. column.name .. (column.isNotNull and " SET NOT NULL" or " DROP NOT NULL"))
            end

            if currentColumn.defaultValue ~= column.defaultValue then
                if engine ~= DatabaseEngine["SQLite"] then
                    table.insert(queries, "ALTER COLUMN " .. column.name .. " SET DEFAULT " .. simple_sql_escape(column.defaultValue))
                else
                    Logger.warning("SQLite does not support changing default values. You will need to manually update the default value of the column " .. column.name .. " in the table " .. tableName .. ".")
                end
            end

            if currentColumn.isPrimaryKey ~= column.isPrimaryKey then
                if column.isPrimaryKey then
                    table.insert(queries, "ADD PRIMARY KEY (" .. column.name .. ")")
                else
                    table.insert(queries, "DROP PRIMARY KEY")
                end
            end

            if currentColumn.isAutoIncrement ~= column.isAutoIncrement then
                if column.isAutoIncrement then
                    table.insert(queries, "ADD AUTOINCREMENT " .. column.name)
                else
                    table.insert(queries, "DROP AUTOINCREMENT " .. column.name)
                end
            end

            if currentColumn.isUnique ~= column.isUnique then
                if column.isUnique then
                    table.insert(queries, "ADD UNIQUE " .. column.name)
                else
                    table.insert(queries, "DROP UNIQUE " .. column.name)
                end
            end
        end
    end

    if withDrops then
        for _, column in pairs(currentColumns) do
            local modelColumn = nil
            for _, c in pairs(modelColumns) do
                if c.name == column.name then
                    modelColumn = c
                    break
                end
            end

            if modelColumn == nil then
                table.insert(queries, "DROP COLUMN " .. column.name)
            end
        end
    end

    for i, query in ipairs(queries) do
        queries[i] = "ALTER TABLE " .. tableName .. " " .. query
    end

    return queries
end

---Automatically migrates the database to the latest version.
---@param withDrops boolean Whether to drop columns that are not in the model definition. (default: false)
function Manager.AutoMigrate(withDrops)
    withDrops = withDrops or false

    for _, model in pairs(Manager._models) do
        local tableName = model.tableName
        local schema = getSqliteTableSchema(tableName)

        if schema == false then
            Logger.debug("Table " .. tableName .. " does not exist. Creating it...")

            local query = generateCreateTableQuery(Manager._engine, tableName, model.columns)
            local result = Manager._Execute(query)
            if result == false then
                Logger.warning("Failed to create table " .. tableName .. ".")
            else
                Logger.debug("Table " .. tableName .. " created successfully.")
            end

        else
            Logger.debug("Table " .. tableName .. " exists. Checking for changes...")

            local queries = generateAlterQueries(Manager._engine, tableName, schema, model.columns, withDrops)
            if #queries > 0 then
                Logger.debug("Table " .. tableName .. " has changes. Updating it...")

                for _, query in ipairs(queries) do
                    local result = Manager._Execute(query)
                    if result == false then
                        Logger.warning("Failed to update table " .. tableName .. ".")
                        break
                    end
                end

                Logger.debug("Table " .. tableName .. " updated successfully.")
            else
                Logger.debug("Table " .. tableName .. " is up to date.")
            end
        end
    end
end