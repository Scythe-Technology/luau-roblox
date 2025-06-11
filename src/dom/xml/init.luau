
return {
    serialize = serialize;
    deserialize = deserialize;
    debug = function(callback: (...any) -> ())
        print = callback::any;
    end
};
