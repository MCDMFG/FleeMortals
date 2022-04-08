function onInit()
    Debug.chat('minion manager load');
end

function isMinion(v)
    rActor = ActorManager.resolveActor(v);
    if not rActor then 
        return false;
    end

    local node = DB.findNode(rActor.sCTNode);
    if rActor.sType == "pc" then
        return false;
    end

    if EffectManager5E.hasEffect(rActor, "Minion") then
        return true;
    end
    
    return false;
end