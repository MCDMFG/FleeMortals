local parseDamageVulnResistImmuneHelperOriginal;
local parseWordsOriginal;

function onInit()
	parseDamageVulnResistImmuneHelperOriginal = ActorManager5E.parseDamageVulnResistImmuneHelper;
	ActorManager5E.parseDamageVulnResistImmuneHelper = parseDamageVulnResistImmuneHelper;
end

function parseDamageVulnResistImmuneHelper(rActor, sField)
	parseWordsOriginal = StringManager.parseWords;
	StringManager.parseWords = parseWords;	
	tResults = parseDamageVulnResistImmuneHelperOriginal(rActor, sField);
	StringManager.parseWords = parseWordsOriginal;
	return tResults;
end

function parseWords(sInput)
	local aWords = parseWordsOriginal(sInput);
	for i = 1, #aWords do
		if aWords[i] == "mundane" then
			aWords[i] = "nonmagical";
		end
	end
	return aWords;
end