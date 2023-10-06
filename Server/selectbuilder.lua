local SelectBuilder = {}

---Creates a new select query builder for the given model.
---@param model table The model to create the query builder for.
---@param withCount boolean Whether to include the count of the query in the result. (default: false)
---@return table queryBuilder The query builder.
function SelectBuilder.new(model, withCount)
    withCount = withCount or false

    local builder = {
        _model = model,
        _withCount = withCount,
        _limit = nil,
        _offset = nil,
        _where = nil,
        _params = {},
    }
    
    ---Sets limit and offset of the query to paginate the results.
    ---This also automatically sets the withCount to true.
    ---@param page integer The one-based page to fetch. (default: 1)
    ---@param perPage integer The number of results per page. (default: 10)
    ---@return table self The query builder.
    function builder:Paginate(page, perPage)
        page = page or 1
        perPage = perPage or 10

        self._limit = perPage
        self._offset = (page - 1) * perPage
        self._withCount = true
        return self
    end

    ---Sets the limit of the query.
    ---@param limit integer The limit of the query.
    ---@return table self The query builder.
    function builder:Limit(limit)
        self._limit = limit
        return self
    end

    ---Sets the offset of the query.
    ---@param offset integer The offset of the query.
    ---@return table self The query builder.
    function builder:Offset(offset)
        self._offset = offset
        return self
    end

    ---Sets the where clause of the query.
    ---@param where string The where clause of the query.
    ---@param ... any The parameters to pass to the where clause.
    ---@return table self The query builder.
    function builder:Where(where, ...)
        self._where = where
        self._params = {...}
        return self
    end

    ---Generates the SQL query.
    ---@return string query The SQL query.
    ---@return table params The parameters to pass to the query.
    function builder:GenerateQuery()
        local query = "SELECT * FROM " .. self._model._definition.tableName

        if self._where ~= nil then
            query = query .. " WHERE " .. self._where
        end

        if self._limit ~= nil then
            query = query .. " LIMIT " .. self._limit
        end

        if self._offset ~= nil then
            query = query .. " OFFSET " .. self._offset
        end

        return query, self._params
    end

    ---Generates the SQL query to count the results. Only works if withCount is true.
    ---@return string query The SQL query.
    ---@return table params The parameters to pass to the query.
    function builder:GenerateCountQuery()
        if not self._withCount then
            error("Cannot generate count query if withCount is false")
        end
        
        local query = "SELECT COUNT(*) as count FROM " .. self._model._definition.tableName

        if self._where ~= nil then
            query = query .. " WHERE " .. self._where
        end

        if self._limit ~= nil then
            query = query .. " LIMIT " .. self._limit
        end

        if self._offset ~= nil then
            query = query .. " OFFSET " .. self._offset
        end

        return query, self._params
    end

    ---Fetches the results of the query and tracks them.
    ---@return table results The results of the query.
    ---@return integer|nil count The count of the query, if withCount is true. Otherwise, nil.
    function builder:Fetch()
        local query, params = self:GenerateQuery()
        local results = model._manager._Select(query, table.unpack(params))

        local count = nil
        if self._withCount then
            local countQuery, countParams = self:GenerateCountQuery()
            count = model._manager._Select(countQuery, table.unpack(countParams))[1]["count"]
        end

        return model.TrackAll(results), count
    end

    return builder
end

return SelectBuilder