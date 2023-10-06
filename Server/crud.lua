local Logger = Package.Require("logger.lua")

local _M = {}

---Adds the operations to the given model.
function _M.AddOperationsToModel(model)
    ---Creates a new empty instance of the given model.
    ---@return table instance The new instance.
    function model.Create(fill)
        fill = fill or true

        local instance = {}
        instance._model = model
        instance._inserted = false
        instance._dirty = {}

        if fill then
            for _, col in pairs(model._definition.columns) do
                instance[col.name] = col.defaultValue
            end
        end

        ---Saves all changes of the given instance to the database.
        function instance:Save()
            if not self._inserted then
                local columns = {}
                local values = {}
                local args = {}
                local idx = 0
                for _, col in pairs(model._definition.columns) do
                    if not col.isAutoIncrement then
                        table.insert(columns, col.name)
                        table.insert(values, ":" .. tostring(idx))
                        table.insert(args, self[col.name])
                        idx = idx + 1
                    end
                end

                model._manager._Execute("INSERT INTO " .. model._definition.tableName .. " (" .. table.concat(columns, ", ") .. ") VALUES (" .. table.concat(values, ", ") .. ")", table.unpack(args))
                self._inserted = true

                if model._definition.softDelete == true then
                    self["deleted_at"] = nil
                end
                
                local primaryKeyName = model._definition:_GetPrimaryKey()
                if self[primaryKeyName] == nil then
                    self[primaryKeyName] = model._manager._LastInsertId()
                end
            else
                local fieldsChanged = self._dirty
                if #fieldsChanged == 0 then
                    return
                end

                local query = "UPDATE " .. model._definition.tableName .. " SET "
                local args = {}
                local idx = 0
                for _, col in pairs(fieldsChanged) do
                    query = query .. col .. " = :" .. tostring(idx) .. ", "
                    table.insert(args, self[col])
                    idx = idx + 1
                end

                query = query:sub(1, -3)
                query = query .. " WHERE id = :" .. tostring(idx)

                table.insert(args, self.id)

                model._manager._Execute(query, table.unpack(args))
            end

            self._dirty = {}
        end

        ---Deletes the given instance from the database.
        function instance:Delete()
            if not self._inserted then
                return
            end

            if model._definition.softDelete == true then
                model._manager._Execute("UPDATE " .. model._definition.tableName .. " SET deleted_at = CURRENT_TIMESTAMP WHERE id = :0", self.id)
                model["deleted_at"] = os.time()
            else
                model._manager._Execute("DELETE FROM " .. model._definition.tableName .. " WHERE id = :0", self.id)
            end
        end

        return setmetatable(instance, {
            __index = function(t, k)
                return rawget(t, k)
            end,
            __newindex = function(t, k, v)
                if rawget(t, k) == v then
                    return
                end

                rawset(t, k, v)

                if k ~= model._definition:_GetPrimaryKey() then -- Primary key cannot get dirty
                    table.insert(t._dirty, k)
                end
            end
        })
    end

    ---Starts the tracking of the given table by converting it to a model.
    ---@param table table The table to track.
    ---@param inserted boolean? Whether the table is already inserted in the database. (default: true)
    ---@return table instance The instance of the given table.
    function model.Track(table, inserted)
        local instance = model.Create(false)
        for _, col in pairs(model._definition.columns) do
            instance[col.name] = table[col.name]
        end
        instance._inserted = inserted or true
        return instance
    end

    ---Starts the tracking of the given tables by converting them to models.
    ---@param tables table The tables to track.
    ---@param inserted boolean? Whether the tables are already inserted in the database. (default: true)
    ---@return table instances The instances of the given tables.
    function model.TrackAll(tables, inserted)
        local instances = {}
        for _, table in pairs(tables) do
            table.insert(instances, model.Track(table, inserted))
        end
        return instances
    end

    ---Returns the first instance that matches the given id.
    function model.Find(id)
        local primaryKeyName = model._definition:_GetPrimaryKey()
        if primaryKeyName == nil then
            error("Model '" .. model._definition.name .. "' has no primary key")
        end

        local query = "SELECT * FROM " .. model._definition.tableName .. " WHERE " .. primaryKeyName .. " = :0"
        if model._definition.softDelete == true then
            query = query .. " AND deleted_at IS NULL"
        end

        local result = model._manager._Select(query, id)

        if #result == 0 then
            return nil
        end

        return model.Track(result[1])
    end

    ---Returns all instances that match the given conditions.
    function model.FindAll()
        local query = "SELECT * FROM " .. model._definition.tableName
        if model._definition.softDelete == true then
            query = query .. " WHERE deleted_at IS NULL"
        end

        local result = model._manager._Select(query)

        return model.TrackAll(result)
    end
end

return _M