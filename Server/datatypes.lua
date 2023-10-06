---Datatypes for the database
DataTypes = {
    STRING = "string",
    TEXT = "text",
    BLOB = "blob",
    BOOLEAN = "boolean",
    INTEGER = "integer",
    UNSIGNED_INTEGER = "unsigned_integer",
    DOUBLE = "double"
}

---Checks if the given type is a valid NanosORM data type
---@param type string The type to check
---@return boolean result Whether the type is valid or not
function DataTypes:IsValid(type)
    for _, v in pairs(self) do
        if v == type then
            return true
        end
    end
    return false
end

---Returns the right SQL type for the given NanosORM data type
---@param engine integer The database engine
---@param type string The NanosORM data type
---@return string sqlType The SQL type
function DataTypes:GetDatabaseType(engine, type) 
    if engine == DatabaseEngine.SQLite then
        if type == DataTypes.STRING then
            return "TEXT"
        elseif type == DataTypes.TEXT then
            return "TEXT"
        elseif type == DataTypes.BLOB then
            return "BLOB"
        elseif type == DataTypes.BOOLEAN then
            return "INTEGER"
        elseif type == DataTypes.INTEGER then
            return "INTEGER"
        elseif type == DataTypes.UNSIGNED_INTEGER then
            return "INTEGER"
        elseif type == DataTypes.DOUBLE then
            return "REAL"
        else
            error("Invalid data type: " .. type)
        end
    elseif engine == DatabaseEngine.MySQL then
        if type == DataTypes.STRING then
            return "VARCHAR(255)"
        elseif type == DataTypes.TEXT then
            return "LONGTEXT"
        elseif type == DataTypes.BLOB then
            return "LONGBLOB"
        elseif type == DataTypes.BOOLEAN then
            return "TINYINT(1)"
        elseif type == DataTypes.INTEGER then
            return "BIGINT"
        elseif type == DataTypes.UNSIGNED_INTEGER then
            return "BIGINT UNSIGNED"
        elseif type == DataTypes.DOUBLE then
            return "DOUBLE"
        else
            error("Invalid data type: " .. type)
        end
    elseif engine == DatabaseEngine.PostgreSQL then
        if type == DataTypes.STRING then
            return "VARCHAR(255)"
        elseif type == DataTypes.TEXT then
            return "TEXT"
        elseif type == DataTypes.BLOB then
            return "BYTEA"
        elseif type == DataTypes.BOOLEAN then
            return "BOOLEAN"
        elseif type == DataTypes.INTEGER then
            return "BIGINT"
        elseif type == DataTypes.UNSIGNED_INTEGER then
            return "BIGINT"
        elseif type == DataTypes.DOUBLE then
            return "DOUBLE PRECISION"
        else
            error("Invalid data type: " .. type)
        end
    else 
        error("Invalid database engine: " .. engine)
    end
end

---Returns the NanosORM data type for the given SQL type
function DataTypes:GetTypeByDatabaseType(engine, type)
    if engine == DatabaseEngine.SQLite then
        if type == "TEXT" then
            return DataTypes.STRING
        elseif type == "BLOB" then
            return DataTypes.BLOB
        elseif type == "INTEGER" then
            return DataTypes.INTEGER
        elseif type == "REAL" then
            return DataTypes.DOUBLE
        else
            error("Invalid data type: " .. type)
        end
    elseif engine == DatabaseEngine.MySQL then
        if type == "VARCHAR(255)" then
            return DataTypes.STRING
        elseif type == "LONGTEXT" then
            return DataTypes.TEXT
        elseif type == "LONGBLOB" then
            return DataTypes.BLOB
        elseif type == "TINYINT(1)" then
            return DataTypes.BOOLEAN
        elseif type == "BIGINT" then
            return DataTypes.INTEGER
        elseif type == "BIGINT UNSIGNED" then
            return DataTypes.UNSIGNED_INTEGER
        elseif type == "DOUBLE" then
            return DataTypes.DOUBLE
        else
            error("Invalid data type: " .. type)
        end
    elseif engine == DatabaseEngine.PostgreSQL then
        if type == "VARCHAR(255)" then
            return DataTypes.STRING
        elseif type == "TEXT" then
            return DataTypes.TEXT
        elseif type == "BYTEA" then
            return DataTypes.BLOB
        elseif type == "BOOLEAN" then
            return DataTypes.BOOLEAN
        elseif type == "BIGINT" then
            return DataTypes.INTEGER
        elseif type == "DOUBLE PRECISION" then
            return DataTypes.DOUBLE
        else
            error("Invalid data type: " .. type)
        end
    else 
        error("Invalid database engine: " .. engine)
    end
end