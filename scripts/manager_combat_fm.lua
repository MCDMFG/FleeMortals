local parseNPCPowerOriginal;
local parseResistancesOriginal;

function onInit()
	parseNPCPowerOriginal = CombatManager2.parseNPCPower;
	CombatManager2.parseNPCPower = parseNPCPower;

	parseResistancesOriginal = CombatManager2.parseResistances;
	CombatManager2.parseResistances = parseResistances;
end

function parseNPCPower(rActor, nodePower, aEffects, bAllowSpellDataOverride)
	local sDisplay = DB.getValue(nodePower, "name", "");
	local sName = StringManager.trim(sDisplay:lower());
	if sName == "supernatural resistance" then
		table.insert(aEffects, "Magic Resistance");
	end

	parseNPCPowerOriginal(rActor, nodePower, aEffects, bAllowSpellDataOverride);
end

function parseResistances(sResistances)
	sResistances = sResistances:gsub("mundane", "nonmagical")
	parseResistancesOriginal(sResistances);
end