-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

local applyDamageOriginal;

function onInit()
    applyDamageOriginal = ActionDamage.applyDamage;
    ActionDamage.applyDamage = applyDamage;
end

function applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
    if MinionManager.isMinion(rTarget) then
        applyDamageMinion(rSource, rTarget, bSecret, sDamage, nTotal)
    else
        applyDamageOriginal(rSource, rTarget, bSecret, sDamage, nTotal)
    end
end

function applyDamageMinion(rSource, rTarget, bSecret, sDamage, nTotal)
    local nTotalHP, nTempHP, nWounds, nDeathSaveSuccess, nDeathSaveFail, nOverkill, nTotalDmg;

    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if not nodeTarget then
		return;
	end
	if sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0);
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0);
		nWounds = DB.getValue(nodeTarget, "wounds", 0);
        nDeathSaveSuccess = DB.getValue(nodeTarget, "deathsavesuccess", 0);
		nDeathSaveFail = DB.getValue(nodeTarget, "deathsavefail", 0);
	else
		return;
	end

    -- Prepare for notifications
    local nConcentrationDamage = 0;
    local bRemoveTarget = false;

    -- Remember current health status
	local sOriginalStatus = ActorHealthManager.getHealthStatus(rTarget);

    -- Decode damage/heal description
	local rDamageOutput = ActionDamage.decodeDamageText(nTotal, sDamage);
	rDamageOutput.tNotifications = {};

    if rDamageOutput.sType == "recovery" then
    elseif rDamageOutput.sType == "heal" then
    elseif rDamageOutput.sType == "temphp" then
    else
        -- Apply any targeted damage effects 
		if rSource and rTarget and rTarget.nOrder then
			ActionDamage.applyTargetedDmgEffectsToDamageOutput(rDamageOutput, rSource, rTarget);
			ActionDamage.applyTargetedDmgTypeEffectsToDamageOutput(rDamageOutput, rSource, rTarget);
		end

        -- Handle avoidance/evasion and half damage
		local isAvoided = false;
		local isHalf = string.match(sDamage, "%[HALF%]");
		local sAttack = string.match(sDamage, "%[DAMAGE[^]]*%] ([^[]+)");
		if sAttack then
			local sDamageState = ActionDamage.getDamageState(rSource, rTarget, StringManager.trim(sAttack));
			if sDamageState == "none" then
				isAvoided = true;
				bRemoveTarget = true;
			elseif sDamageState == "half_success" then
				isHalf = true;
				bRemoveTarget = true;
			elseif sDamageState == "half_failure" then
				isHalf = true;
			end
		end
		if isAvoided then
			table.insert(rDamageOutput.tNotifications, "[EVADED]");
			for kType, nType in pairs(rDamageOutput.aDamageTypes) do
				rDamageOutput.aDamageTypes[kType] = 0;
			end
			rDamageOutput.nVal = 0;
		elseif isHalf then
			table.insert(rDamageOutput.tNotifications, "[HALF]");
			local bCarry = false;
			for kType, nType in pairs(rDamageOutput.aDamageTypes) do
				local nOddCheck = nType % 2;
				rDamageOutput.aDamageTypes[kType] = math.floor(nType / 2);
				if nOddCheck == 1 then
					if bCarry then
						rDamageOutput.aDamageTypes[kType] = rDamageOutput.aDamageTypes[kType] + 1;
						bCarry = false;
					else
						bCarry = true;
					end
				end
			end
            
            rDamageOutput.nVal = math.max(math.floor(rDamageOutput.nVal / 2), 1);
		end
		
		-- Apply damage type adjustments
		local nDamageAdjust, bVulnerable, bResist = ActionDamage.getDamageAdjust(rSource, rTarget, rDamageOutput.nVal, rDamageOutput);
		local nAdjustedDamage = rDamageOutput.nVal + nDamageAdjust;
		if nAdjustedDamage < 0 then
			nAdjustedDamage = 0;
		end
		if bResist then
			if nAdjustedDamage <= 0 then
				table.insert(rDamageOutput.tNotifications, "[RESISTED]");
			else
				table.insert(rDamageOutput.tNotifications, "[PARTIALLY RESISTED]");
			end
		end
		if bVulnerable then
			table.insert(rDamageOutput.tNotifications, "[VULNERABLE]");
		end
		
		-- Prepare for concentration checks if damaged
		nConcentrationDamage = nAdjustedDamage;
		
		-- Reduce damage by temporary hit points
		if nTempHP > 0 and nAdjustedDamage > 0 then
			if nAdjustedDamage > nTempHP then
				nAdjustedDamage = nAdjustedDamage - nTempHP;
				nTempHP = 0;
				table.insert(rDamageOutput.tNotifications, "[PARTIALLY ABSORBED]");
			else
				nTempHP = nTempHP - nAdjustedDamage;
				nAdjustedDamage = 0;
				table.insert(rDamageOutput.tNotifications, "[ABSORBED]");
			end
		end

        -- Handle overkill amount
        nOverkill = nAdjustedDamage - nTotalHP;
        nTotalDmg = nAdjustedDamage;

		-- Apply remaining damage
		if nAdjustedDamage > 0 then 
            -- Remember previous wounds
			local nPrevWounds = nWounds;

            -- If the damage is equal to or greater than the minion's
            -- max HP, it's reduced to 0 hp. Otherwise, no damage.
            if isHalf then
                if nAdjustedDamage >= nTotalHP then
                    nAdjustedDamage = nTotalHP;
                else 
                    table.insert(rDamageOutput.tNotifications, "[MINION]");
                    nAdjustedDamage = 0;
                end
            else
                nAdjustedDamage = nTotalHP;
            end
			
			-- Apply wounds
			nWounds = math.max(nWounds + nAdjustedDamage, 0);
			
			-- Calculate wounds above HP
			local nRemainder = 0;
			if nWounds > nTotalHP then
				nRemainder = nWounds - nTotalHP;
				nWounds = nTotalHP;
			end
			
			-- Deal with remainder damage
			if nRemainder >= nTotalHP then
				table.insert(rDamageOutput.tNotifications, "[DAMAGE EXCEEDS HIT POINTS BY " .. nRemainder.. "]");
				table.insert(rDamageOutput.tNotifications, "[INSTANT DEATH]");
                nDeathSaveFail = 3;
			elseif nRemainder > 0 then
				table.insert(rDamageOutput.tNotifications, "[DAMAGE EXCEEDS HIT POINTS BY " .. nRemainder.. "]");
                if nPrevWounds >= nTotalHP then
					if rDamageOutput.bCritical then
						nDeathSaveFail = nDeathSaveFail + 2;
					else
						nDeathSaveFail = nDeathSaveFail + 1;
					end
				end
			else
				if OptionsManager.isOption("HRMD", "on") and (nAdjustedDamage >= (nTotalHP / 2)) then
					ActionSave.performSystemShockRoll(nil, rTarget);
				end
			end
			
			local nodeTargetCT = ActorManager.getCTNode(rTarget);
			if nodeTargetCT then
				-- Handle stable situation
				EffectManager.removeEffect(nodeTargetCT, "Stable");

				-- Disable regeneration next round on correct damage type
				-- Calculate which damage types actually did damage
				local aTempDamageTypes = {};
				local aActualDamageTypes = {};
				for k,v in pairs(rDamageOutput.aDamageTypes) do
					if v > 0 then
						table.insert(aTempDamageTypes, k);
					end
				end
				local aActualDamageTypes = StringManager.split(table.concat(aTempDamageTypes, ","), ",", true);
				
				-- Check target's effects for regeneration effects that match
				for _,v in pairs(DB.getChildren(nodeTargetCT, "effects")) do
					local nActive = DB.getValue(v, "isactive", 0);
					if (nActive == 1) then
						local bMatch = false;
						local sLabel = DB.getValue(v, "label", "");
						local aEffectComps = EffectManager.parseEffect(sLabel);
						for i = 1, #aEffectComps do
							local rEffectComp = EffectManager5E.parseEffectComp(aEffectComps[i]);
							if rEffectComp.type == "REGEN" then
								for _,v2 in pairs(rEffectComp.remainder) do
									if StringManager.contains(aActualDamageTypes, v2) then
										bMatch = true;
									end
								end
							end
							
							if bMatch then
								EffectManager.disableEffect(nodeTargetCT, v);
							end
						end
					end
				end
			end
		end
		
		-- Update the damage output variable to reflect adjustments
		rDamageOutput.nVal = nAdjustedDamage;
		rDamageOutput.sVal = string.format("%01d", nAdjustedDamage);
    end

	if nWounds < nTotalHP then
		if EffectManager5E.hasEffect(rTarget, "Stable") then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Stable");
		end
		if EffectManager5E.hasEffect(rTarget, "Unconscious") then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Unconscious");
		end
	else
		if not EffectManager5E.hasEffect(rTarget, "Unconscious") then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Unconscious", nDuration = 0 }, true);
		end
	end

	-- Set health fields
	if sTargetNodeType  ~= "pc" then
		DB.setValue(nodeTarget, "deathsavesuccess", "number", math.min(nDeathSaveSuccess, 3));
		DB.setValue(nodeTarget, "deathsavefail", "number", math.min(nDeathSaveFail, 3));
		DB.setValue(nodeTarget, "hptemp", "number", nTempHP);
		DB.setValue(nodeTarget, "wounds", "number", nWounds);
	end

	-- Check for status change
	local bShowStatus = false;
	if ActorManager.isFaction(rTarget, "friend") then
		bShowStatus = not OptionsManager.isOption("SHPC", "off");
	else
		bShowStatus = not OptionsManager.isOption("SHNPC", "off");
	end
	if bShowStatus then
		local sNewStatus = ActorHealthManager.getHealthStatus(rTarget);
		if sOriginalStatus ~= sNewStatus then
			table.insert(rDamageOutput.tNotifications, "[" .. Interface.getString("combat_tag_status") .. ": " .. sNewStatus .. "]");
		end
	end
	
	-- Output results
	ActionDamage.messageDamage(rSource, rTarget, bSecret, rDamageOutput.sTypeOutput, sDamage, rDamageOutput.sVal, table.concat(rDamageOutput.tNotifications, " "));

	-- Remove target after applying damage
	if bRemoveTarget and rSource and rTarget then
		TargetingManager.removeTarget(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rTarget));
	end

	-- Check for required concentration checks
	if nConcentrationDamage > 0 and ActionSave.hasConcentrationEffects(rTarget) then
		if nWounds < nTotalHP then
			local nTargetDC = math.max(math.floor(nConcentrationDamage / 2), 10);
			ActionSave.performConcentrationRoll(nil, rTarget, nTargetDC);
		else
			ActionSave.expireConcentrationEffects(rTarget);
		end
	end

    -- Handle overkill
    if rDamageOutput.sRange == "M" or rDamageOutput.sRange == "R" then
        if (nOverkill or 0) > 0 then
            local rAction = buildOverkillAction(rDamageOutput, nOverkill, nTotalHP, nTotalDmg);
            ActionDamage.performRoll(nil, rSource, rAction);
        end
    end
end

function buildOverkillAction(rDamageOutput, nOverkill, nTotalHp, nTotalDmg)
    local rAction = {};
    rAction.range = rDamageOutput.sRange;
    rAction.label = "Overkill";

    local dmgTypeCount = 0;
    for kType, nType in pairs(rDamageOutput.aDamageTypes) do
        dmgTypeCount = dmgTypeCount + 1;
    end
    
    -- Calculate how much dmg to take from each dmg type
    local deduct = math.max(math.floor(nTotalHp / dmgTypeCount), 1);
    local rem = nTotalHp % dmgTypeCount;

    local dmgClauses = {};
    for kType, nType in pairs(rDamageOutput.aDamageTypes) do
        local clause = {};
        clause.dice = {};
        clause.dmgtype = kType;
        clause.modifier = nType;
        table.insert(dmgClauses, clause);
    end

    -- Sort the clauses by ascending dmg values
    table.sort(dmgClauses, function(a, b) return a.modifier < b.modifier end);

    -- If there are more damage types than overkill damage, then we need to get rid of damage types
    -- Get rid of the types with the lowest damage first
    while dmgTypeCount > nOverkill do
        table.remove(dmgClauses, 1);
        dmgTypeCount = dmgTypeCount - 1;
    end

    -- This probably has edge case bugs in it but initial testing seems to work
    -- For each clause, calculate the percentage of the total damage it did
    -- Then apply that percentage to the overkill amount with a min of 1. 
    -- Since we've ensured that there's never more damage types than overkill dmg, 
    -- this should always return at least 1 damage of each type
    local nTotal = 0;
    for kType, clause in pairs(dmgClauses) do
        local percDmg = clause.modifier / nTotalDmg;
        clause.modifier = math.max(math.floor(percDmg * nOverkill), 1);
        nTotal = nTotal + clause.modifier;
    end
    -- If there's a discrepency it should always be that overkill is higher than the total
    -- Just add that difference to the last entry (which was the highest damage value after the sort)
    if nTotal < nOverkill then
        dmgClauses[dmgTypeCount].modifier = dmgClauses[dmgTypeCount].modifier + (nOverkill - nTotal);
    end

    rAction.clauses = dmgClauses;
    return rAction;
end