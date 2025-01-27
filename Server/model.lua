--[[

  Models are the bones of the ORM. They define the structure of the data that will be stored in the database and retrieved in the exact same format as defined and wanted.
  To create a model, you must use the DefineModel function, which will define the model and its properties.
  
  The DefineModel function receives two parameters:
    - name: The name of the model. It must be unique. NanosORM will create tables based on the principle: First come, first served.
    - model: The model as a table. The DefineModel function will traverse the table and create the necessary columns in the database and bind the structure together.
    
  The function returns the model class adding static functions for CRUD operations and instance functions for instance operations.

  Let's explain how this model table is needed to be structured. The table only consists of columns. Each column is a key-value pair, where the key is the name of the column and the value is the type of the column.
  The type of the column can be an enum type for a direct type, or a table to define even more properties for the column.
  

]]--

Package.Require("manager.lua")

--- @enum DataTypes
DataTypes = {
  UUID = "uuid",
  STRING = "varchar",
  TEXT = "text",
  INTEGER = "integer",
  FLOAT = "float",
  DECIMAL = "decimal",
  BOOLEAN = "boolean",
  DATE = "date",
  TIME = "time",
  DATETIME = "datetime",
  TIMESTAMP = "timestamp",
  JSON = "jsonb",
}

--- @enum OnActions
OnActions = {
  CASCADE = "CASCADE",
  RESTRICT = "RESTRICT",
  SET_NULL = "SET NULL",
  SET_DEFAULT = "SET DEFAULT",
  NO = "NO ACTION",
}

local function isValidDataType(dataType)
  for _, v in pairs(DataTypes) do
    if v == dataType then
      return true
    end
  end

  return false
end

local function transformDataType(dataType)
  if dataType == DataTypes.UUID then
    return "uuid"
  elseif dataType == DataTypes.STRING then
    return "varchar(255)"
  elseif dataType == DataTypes.TEXT then
    return "text"
  elseif dataType == DataTypes.INTEGER then
    return "integer"
  elseif dataType == DataTypes.FLOAT then
    return "float"
  elseif dataType == DataTypes.DECIMAL then
    return "decimal"
  elseif dataType == DataTypes.BOOLEAN then
    return "boolean"
  elseif dataType == DataTypes.DATE then
    return "date"
  elseif dataType == DataTypes.TIME then
    return "time"
  elseif dataType == DataTypes.DATETIME then
    return "datetime"
  elseif dataType == DataTypes.TIMESTAMP then
    return "timestamp"
  elseif dataType == DataTypes.JSON then
    return "jsonb"
  end

  error("Invalid data type")
end

local function getDataTypeValidator(dataType, nullable)
  if dataType == DataTypes.UUID then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string" and string.match(value, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x")
    end
  elseif dataType == DataTypes.STRING then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.TEXT then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.INTEGER then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "number" and math.floor(value) == value
    end
  elseif dataType == DataTypes.FLOAT then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "number"
    end
  elseif dataType == DataTypes.DECIMAL then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "number"
    end
  elseif dataType == DataTypes.BOOLEAN then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "boolean"
    end
  elseif dataType == DataTypes.DATE then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.TIME then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.DATETIME then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.TIMESTAMP then
    return function(value)
      if nullable and value == nil then
        return true
      end

      return type(value) == "string"
    end
  elseif dataType == DataTypes.JSON then
    return function(value)
      return true
    end
  end

  error("Invalid data type")
end

local function buildColumnAssoc(model, col, toModel, assoc, options)
  DB._ASSOC_FINALIZERS = DB._ASSOC_FINALIZERS or {}
  
  local finalize = function ()
    if type(toModel) == "string" then
      toModel = DB._MODELS[toModel]
    end
    
    model._PKS = model._PKS or {}
    model._FKS = model._FKS or {}
    model._M2MS = model._M2MS or {}
    toModel._PKS = toModel._PKS or {}
    toModel._FKS = toModel._FKS or {}
    toModel._M2MS = toModel._M2MS or {}

    options = options or {}
    options.OnDelete = options.OnDelete or OnActions.NO
    options.OnUpdate = options.OnUpdate or OnActions.NO

    if assoc == "OneToOne" or assoc == "OneToMany" then
      if options.__Inverse then
        model, toModel = toModel, model --- Swap models for simplicity
      end

      if #model._PKS > 1 then
        error("OneToOne association cannot be used with composite primary keys")
      elseif #model._PKS == 0 then
        error("OneToOne association must have a primary key")
      end

      -- Create the foreign key
      local fk = {
        Name = model._TABLE .. "_" .. toModel._TABLE .. "_fk",
        RefTable = model._TABLE,
        RefColumn = model._PKS[1],
        OnDelete = options.OnDelete,
        OnUpdate = options.OnUpdate,
      }
      
      if options.__Inverse then
        toModel._FKS[col.Property] = fk
      else
        model._FKS[col.Property] = fk
      end
    elseif assoc == "ManyToMany" then
      if options.__Inverse then
        model, toModel = toModel, model --- Swap models for simplicity
      end

      if #toModel._PKS > 1 then
        error("ManyToMany association cannot be used with composite primary keys")
      end

      if #model._PKS > 1 then
        error("ManyToMany association cannot be used with composite primary keys")
      end

      if #model._PKS == 0 then
        error("ManyToMany association must have a primary key")
      end

      if #toModel._PKS == 0 then
        error("ManyToMany association must have a primary key")
      end

      local m2mTable = {
        Name = model._TABLE .. "_" .. toModel._TABLE .. "_m2m",
        Model = model,
        ToModel = toModel,
        ModelColumn = model._PKS[1],
        ToModelColumn = toModel._PKS[1],
        Columns = {
          {
            Name = model._TABLE .. "_id",
            RefTable = model._TABLE,
            RefColumn = model._PKS[1],
            OnDelete = options.OnDelete,
            OnUpdate = options.OnUpdate,
          },
          {
            Name = toModel._TABLE .. "_id",
            RefTable = toModel._TABLE,
            RefColumn = toModel._PKS[1],
            OnDelete = options.OnDelete,
            OnUpdate = options.OnUpdate,
          },
        }
      }


      if options.__Inverse then
        toModel._M2MS[col] = m2mTable
      else
        model._M2MS[col] = m2mTable
      end

      DB._M2M_TABLES = DB._M2M_TABLES or {}
      table.insert(DB._M2M_TABLES, m2mTable)
    end
  end

  table.insert(DB._ASSOC_FINALIZERS, finalize)
end


--- buildColumn builds a column based on the column name and column data.
--- @param model table The model table.
--- @param name string The name of the column.
--- @param columnData table|DataTypes The column data. It can be a table with more properties or a direct type.
local function buildColumn(model, name, columnData)
  local col = {
    Property = name,
    Name = DB.NamingPolicy(name),
  }

  if type(columnData) == "string" then
    if DB._MODELS[columnData] ~= nil then
      buildColumnAssoc(model, col, DB._MODELS[columnData], "OneToOne", {})

      return col
    elseif isValidDataType(columnData) then
      col.Type = columnData
      col.PrimaryKey = false
      col.Default = nil
      col.NotNull = false
      col.Unique = false
    else
      error("Column " .. name .. "'s type is invalid")
    end
  elseif type(columnData) == "table" then
    if columnData.__ASSOC ~= nil then
      buildColumnAssoc(model, col, columnData.ToModel, columnData.__ASSOC, columnData.Options)

      return col
    elseif columnData.Type.__ASSOC ~= nil then
      buildColumnAssoc(model, col, columnData.Type.ToModel, columnData.Type.__ASSOC, columnData.Type.Options)

      return col
    elseif DB._MODELS[columnData.Type] ~= nil then
      buildColumnAssoc(model, col, DB._MODELS[columnData.Type], "OneToOne", {})

      return col
    elseif isValidDataType(columnData.Type) then
      col.Type = columnData.Type
      col.PrimaryKey = columnData.PrimaryKey or false
      col.Default = columnData.Default or nil
      col.NotNull = columnData.NotNull or false
      col.Unique = columnData.Unique or false
    else
      error("Column " .. name .. "'s type is invalid")
    end
  end
  
  if col.Type == nil then
    error("Column " .. name .. " has no type defined")
  end

  if col.PrimaryKey then
    col.NotNull = true
    col.Unique = true

    model._PKS = model._PKS or {}
    table.insert(model._PKS, name)
  end

  col.SqlType = transformDataType(col.Type)
  col._validate = getDataTypeValidator(col.Type, not col.NotNull)

  return col
end

--- OneToOne defines a one-to-one association between two models. The toModel will have a foreign key to the owning model.
function OneToOne(toModel, options)
  return {
    __ASSOC = "OneToOne",
    ToModel = toModel,
    Options = options or {},
  }
end

--- OneToMany defines a one-to-many association between two models. The toModel will have a foreign key to the owning model.
function OneToMany(toModel, options)
  return {
    __ASSOC = "OneToMany",
    ToModel = toModel,
    Options = options or {},
  }
end

--- ManyToMany defines a many-to-many association between two models. A third table will be created to store the relationship between the two models.
function ManyToMany(toModel, options)
  return {
    __ASSOC = "ManyToMany",
    ToModel = toModel,
    Options = options or {},
  }
end

--- Inverse returns the inverse of the association. It is used to define the inverse of the association when the association is defined in the toModel.
function Inverse(assoc)
  return {
    __ASSOC = assoc.__ASSOC,
    __Inverse = true,
    ToModel = assoc.ToModel,
    Options = assoc.Options or {},
  }
end

--- Col defines a column in the model. This can be used instead of defining the column directly in the model table as a fluent interface.
--- @param type DataTypes The type of the column.
function Col(type)
  local col = {Type = type}

  function col:PrimaryKey()
    self.PrimaryKey = true
    return self
  end

  function col:Default(value)
    if value == nil then
      if self.Type == DataTypes.UUID then
        self.Default = "uuid_generate_v4()"
      elseif self.Type == DataTypes.DATE then
        self.Default = "NOW()"
      elseif self.Type == DataTypes.TIME then
        self.Default = "NOW()"
      elseif self.Type == DataTypes.DATETIME then
        self.Default = "NOW()"
      elseif self.Type == DataTypes.TIMESTAMP then
        self.Default = "NOW()"
      else
        error("Default value for column " .. self.Name .. " is invalid")
      end
    else
      self.Default = value
    end

    return self
  end

  function col:NotNull()
    self.NotNull = true
    return self
  end

  function col:Unique()
    self.Unique = true
    return self
  end

  return col
end

--- DefineModel defines a model/entity class in the ORM. The function is required to tell NanosORM about the model and its properties.
--- Based on the created model, NanosORM will create the necessary tables in the database and provide the necessary functions to interact with it.
---
--- @param name string The name of the model. It must be unique. NanosORM will create tables based on the principle: First come, first served.
--- @param model table The model as a table. The DefineModel function will traverse the table and create the necessary columns in the database and bind the structure together.
--- @param useSoftDelete boolean? Whether to use soft delete or not. Default is false.
function DefineModel(name, model, useSoftDelete)
  if DB._isFinalized then
    error("Models are already finalized")
  end

  useSoftDelete = useSoftDelete or false

  local modelBase = {
    _VERSION = Package.GetVersion(),
    _TABLE = DB.NamingPolicy(name),
    _MODELNAME = name,
    _SD = useSoftDelete,
    _COLUMNS = {},
    _PKS = {},
    _FKS = {},
    _DB = DB,
  }

  DB[name] = modelBase
  DB._MODELS[name] = modelBase

  --- _wrap wraps the given data into the model instance.
  modelBase._wrap = function(data, pks)
    local instance = {
      _VERSION = modelBase._VERSION,
      _TABLE = modelBase._TABLE,
      _COLUMNS = modelBase._COLUMNS,
      _MODEL = modelBase,
      _DIRTY = {},
      _PKS = pks,
    }

    for columnName, _ in pairs(modelBase._COLUMNS) do
      instance[columnName] = data[columnName]
    end

    setmetatable(instance, {
      __index = function(self, key)
        return self[key]
      end,
      __newindex = function(self, key, value)
        if modelBase._COLUMNS[key] then
          local col = modelBase._COLUMNS[key]
          if col._validate(value) then
            
            if self[key] ~= value then
              self._DIRTY[key] = true
            end

            self[key] = value
          end

          error("Invalid value for column " .. key)
        end
      end,
    })

    --- Save saves the instance changes to the database. This will only update dirty columns.
    function instance:Save()
      self._MODEL:Save(self)
    end

    --- Delete deletes the instance from the database.
    --- @param hard boolean Whether to hard delete the instance or not. Default is false. If false and the model is using soft delete, it will only set the deleted_at column.
    function instance:Delete(hard)
      self._MODEL:Delete(self, hard or false)
    end

    return instance
  end
  
  for columnName, columnData in pairs(model) do
    local column = buildColumn(modelBase, columnName, columnData)

    modelBase._COLUMNS[columnName] = column
  end

  function modelBase:New(data)
    return self._wrap(data or {}, nil)
  end

  function modelBase:Save(instance)
    DB.Save(self, instance)
  end

  function modelBase:Delete(instance, hard)
    DB.Delete(self, instance, hard)
  end

  function modelBase:FindWhere(where, lazy)
    return DB.FindWhere(self, where, lazy)
  end

  function modelBase:FindOneWhere(where, lazy)
    return DB.FindOneWhere(self, where, lazy)
  end

  function modelBase:Find(lazy)
    return modelBase:FindWhere({}, lazy)
  end

  function modelBase:FindOne(lazy)
    return modelBase:FindOneWhere({}, lazy)
  end

  function modelBase:QueryBuilder()
    return DB.QueryBuilder(self)
  end

  return modelBase
end