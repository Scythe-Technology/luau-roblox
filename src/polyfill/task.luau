--!strict
--!native
--!optimize 2
if (type(_VERSION) == "string") then
    if (string.sub(_VERSION, 1, 4) == "zune") then
        return zune.task;
    elseif (string.sub(_VERSION, 1, 4) == "Lune") then
        return require("@lune/task")
    end
end

return {
    spawn = function(f: (() -> ()) | thread): thread
        if (type(f) == "function") then
            local thread = coroutine.create(f);
            assert(coroutine.resume(thread));
            return thread
        end
        assert(coroutine.resume(f));
        return f;
    end,
    wait = function(f: (() -> ()) | thread): (() -> ())
        error("Not implemented");
    end,
    delay = function(time: number, f: (() -> ()) | thread): thread
        error("Not implemented");
    end,
    defer = function(f: (() -> ()) | thread): thread
        error("Not implemented");
    end,
};
