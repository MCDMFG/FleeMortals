function onInit()
end

function isMinion(v)
    rActor = ActorManager.resolveActor(v);
    if not rActor then 
        return false;
    end

    if rActor.sType == "pc" then
        return false;
    end

    local node = DB.findNode(rActor.sCTNode);
    if DB.getValue(node, "role", ""):lower() == "minion" then
        return true;
    end

    if EffectManager5E.hasEffect(rActor, "Minion") then
        return true;
    end
    
    return false;
end