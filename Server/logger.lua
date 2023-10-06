local Logger = {_debug = false}

function Logger.debug(message)
    if Logger._debug then
        print("NanosORM-DBG:\t" .. message)
    end
end

function Logger.warning(message)
    print("NanosORM-WRN:\t" .. message)
end

function Logger.enableDebug()
    Logger._debug = true
end

return Logger