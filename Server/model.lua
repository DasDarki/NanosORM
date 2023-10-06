Package.Require("datatypes.lua")

local Logger = Package.Require("logger.lua")
local Manager = Package.Require("manager.lua")
local CRUD = Package.Require("crud.lua")

local function isValidIdentifier(identifier)
    if type(identifier) ~= "string" then
        return false
    end

    if identifier:match("^[a-zA-Z0-9_]+$") == nil then
        return false
    end

    return true
end

--[[===================== MODEL DEFINITION =====================]]--
local ModelDefinition = {}
ModelDefinition.__index = ModelDefinition
ModelDefinition.__type = "ModelDefinition"

---Creates a new instance of Model
function ModelDefinition.new(name)
    local self = setmetatable({}, ModelDefinition)

    self.tableName = name
    self.columns = {}

    return self
end

---Returns the table name
function ModelDefinition:__tostring()
    return self.tableName
end

---Adds a new column to the model definition
---@return table|false builder A field builder to specify more options. False if an error occured.
function ModelDefinition:Field(name, _type) 
    if not isValidIdentifier(name) then
        Logger.warning("Invalid identifier '" .. name .. "'")
        return false
    end

    if not DataTypes:IsValid(_type) then
        Logger.warning("Invalid data type '" .. _type .. "'")
        return false
    end

    local col = {
        name = name,
        ["type"] = _type,
        isNotNull = true,
        isPrimaryKey = false,
        isUnique = false,
        isAutoIncrement = false,
        defaultValue = nil,
        foreignKey = nil,
    }

    self.columns[name] = col

    col.__index = col
    col.__type = "Field"

    ---Sets the column as primary key
    function col:PrimaryKey()
        col.isPrimaryKey = true
        return self
    end

    ---Sets the column as auto increment
    function col:AutoIncrement()
        if col.isPrimaryKey ~= true then
            Logger.warning("You can only set a column as auto increment if it is a primary key")
        end

        self.isAutoIncrement = true
        return self
    end

    ---Sets the column as nullable
    function col:Nullable()
        self.isNotNull = false 
        return self
    end

    ---Sets the column as unique
    function col:Unique()
        self.isUnique = true
        return self
    end

    ---Sets the default value of the column
    function col:Default(value)
        self.defaultValue = value
        return self
    end

    ---Makes the column a foreign key to the given model.
    ---@param model table The model to reference to
    ---@param column string The column to reference to. This is optional, if not given the primary key of the model will be used.
    ---@return table builder The foreign key builder to specify on delete and on update actions.
    function col:ForeignKey(model, column)
        local primKey = column or model:_GetPrimaryKey()
        local foreignKey = {
            table = model.tableName,
            column = primKey
        }

        self.foreignKey = foreignKey
        self.foreignKey.__index = foreignKey
        self.foreignKey.__type = "ForeignKey"

        local _this = self

        ---Sets the on delete action
        function foreignKey:OnDelete(action)
            self.onDelete = action
            return self
        end

        ---Sets the on update action
        function foreignKey:OnUpdate(action)
            self.onUpdate = action
            return self
        end

        ---Returns back to the column builder
        function foreignKey:End()
            return _this
        end

        return self.foreignKey
    end

    return col
end

---Returns the primary key of the model or nil if no primary key is set
function ModelDefinition:_GetPrimaryKey()
    for _, col in pairs(self.columns) do
        if col.isPrimaryKey then
            return col.name
        end
    end

    return nil
end

function ModelDefinition:_GetColumnByName(name)
    return self.columns[name]
end

---Defines a database entity model.
---@param name string The name of the model
---@param onDefine function The function to define the model. Gets called with the model builder as first argument.
---@param withSoftDelete boolean Whether to add a soft delete column to the model or not. Defaults to false.
---@return table model The model.
function Manager.DefineModel(name, onDefine, withSoftDelete)
    if not isValidIdentifier(name) then
        error("Invalid model name '" .. name .. "'")
    end

    if type(onDefine) ~= "function" then
        error("onDefine must be a function")
    end

    if Manager._models[name] ~= nil then
        error("Model '" .. name .. "' is already defined")
    end

    withSoftDelete = withSoftDelete or false

    local definition = ModelDefinition.new(name)
    onDefine(definition)

    local primKey = definition:_GetPrimaryKey()
    if primKey == nil then
        definition:Field("id", DataTypes.UNSIGNED_INTEGER):PrimaryKey():AutoIncrement()
    end

    local deletedAt = definition:_GetColumnByName("deleted_at")
    if withSoftDelete and deletedAt == nil then
        definition:Field("deleted_at", DataTypes.INTEGER):Nullable()
    end

    definition.softDelete = withSoftDelete
    Manager._models[name] = definition

    local model = {}
    model.__type = "Model"
    model._definition = definition
    model._manager = Manager

    CRUD.AddOperationsToModel(model)

    return model
end