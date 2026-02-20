local addonName, addon = ...
local Reputable = addon.a

local debug = Reputable.debug

local function GetAddOnMetadataCompat(name, field)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(name, field)
	end
	if GetAddOnMetadata then
		return GetAddOnMetadata(name, field)
	end
	return nil
end

local version = GetAddOnMetadataCompat(addonName, "Version") or 9999;
local author = GetAddOnMetadataCompat(addonName, "Author") or "";

local LDB = LibStub("LibDataBroker-1.1")
local reputableDataBroker = nil
local reputableMM = nil
local reputableMinimapIcon = LibStub("LibDBIcon-1.0")

local playerFaction = UnitFactionGroup("player")
local playerName = UnitName("player")

-- Open options in both legacy Interface Options and modern Settings UI
local function OpenOptionsCompat()
	-- Legacy Interface Options
	if type(InterfaceOptionsFrame_OpenToCategory) == "function" then
		InterfaceOptionsFrame_OpenToCategory(addonName)
		InterfaceOptionsFrame_OpenToCategory(addonName)
		return
	end
	if type(InterfaceOptionsFrame_Show) == "function" and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
		InterfaceOptionsFrame_Show()
		InterfaceOptionsFrame_OpenToCategory(addonName)
		InterfaceOptionsFrame_OpenToCategory(addonName)
		return
	end

	-- Modern Settings
	if Settings and type(Settings.OpenToCategory) == "function" then
		local id
		if addon then
			id = addon.settingsCategoryID
			if not id and addon.optionsPanel then
				id = addon.optionsPanel.__settingsCategoryID
			end
		end
		if id then
			Settings.OpenToCategory(id)
		else
			Settings.OpenToCategory(addonName)
		end
	end
end

local server = GetRealmName()
local level = UnitLevel("player")

-- Assigned by createGUI(); lets loadHTML notify the active content layout to
-- recalculate true scroll height after text changes.
local RefreshMainScrollLayout

Reputable.waitingForItemHTML = {}

function Reputable:loadHTML(pageName)
	Reputable:addonMessage()
	if pageName then
		if pageName == 'attune560' then pageName = 'attune269' end -- Send both CoT dungeons to the same page
		Reputable.tabOpen = pageName
	end

	--debug("Showing page", Reputable.tabOpen)

	local htmlObj = Reputable.guiTabs[Reputable.tabOpen].html
	local main = htmlObj.header
	local right = "<html><body text='#FFFFFF'><h1><br/></h1><br/>"
	local tab1 = "<html><body text='#FFFFFF'><h1><br/></h1><br/>"

	for i = 1, htmlObj.i - 1 do
		local leftLine = "<br/>"
		local rightLine = "<br/>"
		local tabLine = "<br/>"
		if htmlObj.main[i].tab then
			tabLine = htmlObj.main[i].text
		else
			leftLine = htmlObj.main[i].text
		end
		if htmlObj.right[i] and htmlObj.iRight >= i then rightLine = htmlObj.right[i] end

		main = main .. "<" .. htmlObj.main[i].tag .. ">" .. leftLine .. "</" .. htmlObj.main[i].tag .. ">"
		right = right ..
			"<" .. htmlObj.main[i].tag .. " align='right'>" .. rightLine .. "</" .. htmlObj.main[i].tag .. ">"
		tab1 = tab1 .. "<" .. htmlObj.main[i].tag .. ">" .. tabLine .. "</" .. htmlObj.main[i].tag .. ">"
	end

	-- Debug/compat: if no lines were generated for this page, show a visible placeholder
	if not htmlObj.i or htmlObj.i <= 1 then
		main = main ..
			"<p><br/><br/><b>No content generated for this page.</b><br/>This usually means the page data builder didn't add any rows, or the client API changed in a way that prevents data collection.</p>"
	end

	-- Optional legacy text renderer (disabled by default).
	if Reputable.gui and Reputable.gui.useTextRenderer and Reputable.gui.text_main and Reputable.gui.text_right then
		-- Ensure active renderer visibility is correct even if layout hasn't rerun yet.
		if Reputable.gui.html_main then Reputable.gui.html_main:Hide() end
		if Reputable.gui.html_right then Reputable.gui.html_right:Hide() end
		if Reputable.gui.html_tab1 then Reputable.gui.html_tab1:Hide() end
		Reputable.gui.text_main:Show()
		Reputable.gui.text_right:Show()
		if Reputable.gui.text_main.SetTextColor then Reputable.gui.text_main:SetTextColor(1, 1, 1, 1) end
		if Reputable.gui.text_right.SetTextColor then Reputable.gui.text_right:SetTextColor(1, 1, 1, 1) end

		local function htmlToText(s)
			if not s then return "" end
			s = tostring(s)
			-- normalize line breaks for common HTML-ish tags used by the addon
			s = s:gsub("<br%s*/?>", "\n")
			s = s:gsub("</p%s*>", "\n")
			s = s:gsub("<p[^>]*>", "")
			s = s:gsub("</h[1-6]%s*>", "\n")
			s = s:gsub("<h[1-6][^>]*>", "")
			-- drop any remaining tags
			s = s:gsub("</?[%w]+[^>]*>", "")
			s = s:gsub("&nbsp;", " ")
			-- collapse excessive blank lines
			s = s:gsub("\n\n\n+", "\n\n")
			-- normalize inline texture tags (icons) so they align with text baseline on newer clients
			local function textureYOffset(h)
				return 0
			end
			-- Normalize inline texture tags (icons) so they align with the text baseline on newer clients.
			-- Force all variants into the full form: |Tpath:w:h:x:y|t
			-- Full format with texcoords: |Tpath:w:h:x:y:fileW:fileH:left:right:top:bottom|t
			s = s:gsub("%|T([^:|]+):(%d+):(%d+):([%-%d]+):([%-%d]+):([^|]+)%|t", function(path, w, h, x, y, rest)
				local ny = textureYOffset(h)
				return ("|T%s:%s:%s:%s:%d:%s|t"):format(path, w, h, x, ny, rest)
			end)
			-- Short format: |Tpath:w:h:x:y|t
			s = s:gsub("%|T([^:|]+):(%d+):(%d+):([%-%d]+):([%-%d]+)%|t", function(path, w, h, x, y)
				local ny = textureYOffset(h)
				return ("|T%s:%s:%s:%s:%d|t"):format(path, w, h, x, ny)
			end)
			s = s:gsub("%|T([^:|]+):(%d+):(%d+)%|t", function(path, w, h)
				local ny = textureYOffset(h)
				return ("|T%s:%s:%s:0:%d|t"):format(path, w, h, ny)
			end)
			s = s:gsub("%|T([^:|]+):(%d+)%|t", function(path, size)
				local ny = textureYOffset(size)
				return ("|T%s:%s:%s:0:%d|t"):format(path, size, size, ny)
			end)
			-- Ensure a space after an icon when immediately followed by text
			s = s:gsub("(%|t)(%S)", "%1 %2")
			return s
		end

		-- addTextBlock: accepts an array of pre-processed lines (already through htmlToText).
		-- IMPORTANT: do NOT call htmlToText again here; the left and right arrays must have
		-- identical line counts, and a second htmlToText pass can collapse newlines differently
		-- in each frame, causing the two columns to desynchronise.
		local function addTextBlock(frame, linesArray)
			frame:Clear()
			local lineCount = #linesArray
			if lineCount == 0 then
				frame:AddMessage(" ")
				lineCount = 1
			else
				-- Insert in forward order (BOTTOM insert mode).
				-- Line 1 is added first ("oldest") and displayed at the top
				-- when scrolled to the beginning.
				for i = 1, lineCount do
					local line = linesArray[i]
					if not line or line == "" then line = " " end
					frame:AddMessage(line)
				end
			end
			frame.__repLineCount = lineCount
			-- Scroll to show the beginning of the document.
			-- With BOTTOM insert mode, "oldest" = first lines = top of document.
			if frame.ScrollToTop then
				frame:ScrollToTop()
			end
		end

		local tMain = {}
		local tRight = {}
		-- Helper: split a text string into individual lines
		local function splitTextLines(text)
			local result = {}
			for line in (text .. "\n"):gmatch("(.-)\n") do
				tinsert(result, line)
			end
			if #result == 0 then tinsert(result, " ") end
			return result
		end
		-- Build text output directly from structured page rows.
		-- Using the pre-expanded HTML string here causes duplicated rows and lots of
		-- placeholder <br/> entries that become giant blank regions in Anniversary.
		local headerText = htmlToText(htmlObj.header or "")
		headerText = headerText:gsub("\n+", " "):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		-- Show title in the dedicated centered FontString above the content
		if Reputable.gui.text_title then
			if headerText ~= "" then
				Reputable.gui.text_title:SetText(headerText)
				Reputable.gui.text_title:Show()
			else
				Reputable.gui.text_title:SetText("")
				Reputable.gui.text_title:Hide()
			end
		end
		if not htmlObj.i or htmlObj.i <= 1 then
			tinsert(tMain, "[No content generated for this page]")
			tinsert(tRight, " ")
			tinsert(tMain, "If this persists, page data generation failed.")
			tinsert(tRight, " ")
		end
		for i = 1, htmlObj.i - 1 do
			local leftLine, rightLine, tabLine = "", "", ""
			if htmlObj.main[i].tab then
				-- In the original UI these lines were rendered into a separate tab pane.
				-- On Anniversary we render them into the main pane as well, otherwise large parts (e.g. quest lists) disappear.
				tabLine = htmlObj.main[i].text or ""
				leftLine = tabLine
			else
				leftLine = htmlObj.main[i].text or ""
			end
			if htmlObj.right[i] and htmlObj.iRight >= i then rightLine = htmlObj.right[i] end

			local leftText = htmlToText(leftLine)
			local rightText = htmlToText(rightLine)

			-- Trim leading/trailing whitespace and newlines from each row.
			-- This prevents <br/> spacers from producing double blank lines
			-- (htmlToText converts <br/> to \n, and splitTextLines would turn
			-- a lone \n into two empty entries).
			leftText = leftText:gsub("^[\n%s]+", ""):gsub("[\n%s]+$", "")
			rightText = rightText:gsub("^[\n%s]+", ""):gsub("[\n%s]+$", "")

			if leftText == "" and rightText == "" then
				-- Both sides are blank (spacer row): add a single blank line.
				tinsert(tMain, " ")
				tinsert(tRight, " ")
			else
				if leftText == "" then leftText = " " end
				if rightText == "" then rightText = " " end
				-- Indent tab content (quests/dungeons listed under headers)
				local indent = ""
				if htmlObj.main[i].tab then indent = "    " end
				-- Ensure both sides have the same number of lines for synchronized scrolling.
				local lLines = splitTextLines(leftText)
				local rLines = splitTextLines(rightText)
				local count = math.max(#lLines, #rLines)
				for j = 1, count do
					tinsert(tMain, indent .. (lLines[j] or " "))
					tinsert(tRight, rLines[j] or " ")
				end
			end
		end

		-- No viewport padding needed: SetJustifyV("TOP") on the ScrollingMessageFrame
		-- already positions short content at the top of the frame.

		addTextBlock(Reputable.gui.text_main, tMain)
		addTextBlock(Reputable.gui.text_right, tRight)
		if RefreshMainScrollLayout then
			RefreshMainScrollLayout(true)
		end
		return
	end

	-- Primary renderer: native SimpleHTML layers.
	if Reputable.gui and Reputable.gui.text_main then Reputable.gui.text_main:Hide() end
	if Reputable.gui and Reputable.gui.text_right then Reputable.gui.text_right:Hide() end
	if Reputable.gui and Reputable.gui.text_title then Reputable.gui.text_title:Hide() end
	if Reputable.gui and Reputable.gui.html_main then
		Reputable.gui.html_main:SetAlpha(1)
		Reputable.gui.html_main:Show()
	end
	if Reputable.gui and Reputable.gui.html_right then
		Reputable.gui.html_right:SetAlpha(1)
		Reputable.gui.html_right:Show()
	end
	if Reputable.gui and Reputable.gui.html_tab1 then
		Reputable.gui.html_tab1:SetAlpha(1)
		Reputable.gui.html_tab1:Show()
	end
	Reputable.gui.html_main:SetText(main .. "</body></html>")
	Reputable.gui.html_right:SetText(right .. "</body></html>")
	Reputable.gui.html_tab1:SetText(tab1 .. "</body></html>")
	if RefreshMainScrollLayout then
		RefreshMainScrollLayout(true)
	end

	-- Some Anniversary builds report/behave as if SimpleHTML failed to render.
	-- Auto-fallback to text renderer if we detect empty content height.
	if C_Timer and C_Timer.After and Reputable.gui and not Reputable.gui.useTextRenderer then
		C_Timer.After(0, function()
			if not Reputable.gui or Reputable.gui.useTextRenderer then return end
			local h = 0
			if Reputable.gui.html_main and Reputable.gui.html_main.GetContentHeight then
				h = Reputable.gui.html_main:GetContentHeight() or 0
			end
			if h < 5 and not Reputable.gui.__repHtmlFallbackTried then
				Reputable.gui.__repHtmlFallbackTried = true
				Reputable.gui.useTextRenderer = true
				Reputable:loadHTML(pageName)
			end
		end)
	end
end

local function createSubTitle(frame, name, text)
	frame.y = frame.y - 10
	frame["subtitle_" .. name] = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame["subtitle_" .. name]:SetText(text)
	frame["subtitle_" .. name]:SetPoint("TOPLEFT", 10, frame.y)
	frame.y = frame.y - 20
end
local function createMenuBTN(frame, name, text)
	frame["menuBTN_" .. name] = CreateFrame('Button', name, frame, "OptionsListButtonTemplate")
	frame["menuBTN_" .. name].name = name
	frame["menuBTN_" .. name]:SetText(text)
	frame["menuBTN_" .. name]:SetNormalFontObject("GameFontWhiteSmall")
	frame["menuBTN_" .. name]:SetPoint("TOPLEFT", 20, frame.y)
	frame["menuBTN_" .. name]:SetScript("OnClick", function(self) Reputable:loadHTML(self.name) end)
	frame.y = frame.y - 20
end

local function addLineToHTML(page, tag, text, tab, i)
	local index = page.i
	if i then index = i end
	if not page.main[index] then page.main[index] = {} end

	page.main[index].tag = tag
	page.main[index].text = text
	page.main[index].tab = tab

	if not i then page.i = index + 1 end
end

function Reputable:tryMakeItemLink(itemID, cat, page, i, icon, pre, post)
	if not pre then pre = "" end
	if not post then post = "" end
	local link = Reputable:createLink("item", itemID, nil, nil, nil, nil)
	local haveItem = ""
	if icon then haveItem = Reputable:icons(GetItemCount(itemID, true), -9) end
	local returnLink = pre ..
		"|cff9d9d9d|Hitem:" .. itemID .. "::::::::::::|h[Item: " .. itemID .. "]|h|r" .. haveItem .. post
	if link ~= nil then
		returnLink = pre .. link .. haveItem .. post
	else
		if not Reputable.waitingForItemHTML[itemID] then Reputable.waitingForItemHTML[itemID] = {} end
		tinsert(Reputable.waitingForItemHTML[itemID], { cat, page, i, icon, pre, post })
	end
	if page == "right" then
		Reputable.guiTabs[cat].html[page][i] = returnLink
	else
		local tab
		if page == 'tab' then tab = true end
		addLineToHTML(Reputable.guiTabs[cat].html, "p", returnLink, tab, nil)
	end
	return returnLink
end

Reputable.guiCats = {
	[1] = { name = "events", label = BATTLE_PET_SOURCE_7 },
	[2] = { name = "dungeons", label = DUNGEONS },
	[3] = { name = "reputations", label = REPUTATION },
	[4] = { name = "attunements", label = "Attunements" },
	[5] = { name = "reputationsC", label = EXPANSION_NAME0 .. " " .. REPUTATION },
	[6] = { name = "reputationsUnsorted", label = EXPANSION_NAME0 .. " (Unsorted)" },
	[7] = { name = "attunementsC", label = EXPANSION_NAME0 .. " Attunements" },
}
Reputable.guiTabs = {
	{ name = "midsummer",    title = "Midsummer Fire Festival",                  label = "Midsummer Fire Festival",                  cat = 1 },
	{ name = "brewfest",     title = "Brewfest",                                 label = "Brewfest",                                 cat = 1 },
	{ name = "dungeons",     title = EXPANSION_NAME1 .. " " .. DUNGEONS,         label = EXPANSION_NAME1,                            cat = 2 },
	{ name = "dailies",      title = ALL .. " " .. DAILY .. " " .. QUESTS_LABEL, label = ALL .. " " .. DAILY .. " " .. QUESTS_LABEL, cat = 3 },
	{ faction = 946 },
	{ faction = 947 },
	{ faction = 942 },
	{ faction = 1011 },
	{ faction = 933 },
	{ faction = 989 },
	{ faction = 935 },
	{ faction = 967 },
	{ faction = 970 },
	{ faction = 978 },
	{ faction = 941 },
	{ faction = 1012 },
	{ faction = 934 },
	{ faction = 932 },
	{ faction = 1031 },
	{ faction = 1038 },
	{ instance = 532 },
	{ instance = "Nightbane" },
	{ instance = 555 },
	{ instance = 552 },
	{ instance = 269 },
	{ instance = 540 },
	{ instance = 550 },
	{ instance = 548 },
	--{ instance = 249, cat = 6 }, -- testing (ony)
	--{ faction =  529 }, -- testing argentdawn
	--{ faction =  69, cat = 6 }, -- testing darnassus
}
local classicFactionList = {
	{ faction = 529 }, -- Arengt Dawn
	--	{ faction = 87	},	-- Bloodsail Buccaneers
	{ faction = 21 }, -- Booty Bay
	{ faction = 910 }, -- Brood of Nozdormu
	{ faction = 609 }, -- Cenarion Circle
	--	{ faction = 909	},	-- Darkmoon Faire
	{ faction = 530 }, -- Darkspear Trolls
	{ faction = 69 }, -- Darnassus
	--	{ faction = 510	},	-- The Defilers	(pvp)
	{ faction = 577 }, -- Everlook
	{ faction = 930 }, -- Exodar
	--	{ faction = 729	},	-- Frostwolf Clan	(pvp)
	{ faction = 369 }, -- Gadgetzan
	{ faction = 54 }, -- Gnomeregan Exiles
	--	{ faction = 749	},	-- Hydraxian Waterlords
	{ faction = 47 }, -- Ironforge
	--	{ faction = 509	},	-- The League of Arathor	(pvp)
	{ faction = 76 }, -- Orgrimmar
	{ faction = 470 }, -- Ratchet
	--	{ faction = 349	},	-- Ravenholdt	(Rogue)
	--	{ faction = 809	},	-- Shen'dralar	(Dire Maul)
	{ faction = 911 }, -- Silvermoon City
	--	{ faction = 890	},	-- Silverwing Sentinels	(pvp)
	--	{ faction = 730	},	-- Stormpike Gaurd	(pvp)
	{ faction = 72 }, -- Stormwind
	{ faction = 59 }, -- Thorium Brotherhood
	{ faction = 81 }, -- Thunder Bluff
	{ faction = 576 }, -- Timbermaw Hold
	{ faction = 68 }, -- Undercity
	--	{ faction = 889	},	-- Warsong Outriders	(pvp)
	--	{ faction = 589	},	-- Wintersaber Trainers
	{ faction = 270 }, -- Zandalar Tribe
}
local classicFactionPages = {}
for _, f in ipairs(classicFactionList) do
	--print( k,v, classicFactionList[ k ].faction )
	--print( f.faction)
	classicFactionPages[f.faction] = true
	table.insert(Reputable.guiTabs, { faction = f.faction, cat = 6 })
end
local classicAttunePages = { [249] = true }
for instanceID in pairs(classicAttunePages) do
	table.insert(Reputable.guiTabs, { instance = instanceID, cat = 7 })
end

-- Layout model for the 3 SimpleHTML layers.
-- IMPORTANT: Some 2.5.5 UI builds ship a SimpleHTMLTemplate that includes
-- background textures. If a layer spans the whole content area, it can
-- "cover" the other layers and everything looks empty.
--
-- We therefore:
--  1) Strip any template textures from each layer to keep them transparent.
--  2) Size/anchor layers explicitly into a two-column layout.
--
-- main: left column (text)
-- tab1: overlay on main (tabbed lines), slightly indented
-- right: right column (icons/locks/currency)
local htmlLayers = {
	["main"]  = {},
	["tab1"]  = {},
	["right"] = {},
}

local function addDungeonToHTML(thisPage, dungeonID, limit, pre, post)
	local showNormal = true
	local showHeroic = true
	if not pre then pre = "" end
	if not post then post = "" end
	if limit == 0 then
		showHeroic = false
	elseif limit == 1 then
		showNormal = false
	end
	local d = Reputable.instance[dungeonID]
	local icon
	if d.icon then icon = "|TInterface\\AddOns\\Reputable\\icons\\" .. d.icon .. ":12:12:0:-10:64:64:5:59:5:59|t " end
	if d.accessKey and thisPage.pagetype ~= "attunement" then
		Reputable:tryMakeItemLink(d.accessKey, thisPage.name, "right", thisPage.i, true, nil, nil)
		thisPage.iRight = thisPage.i
	end
	local levelLock = ''
	local accessKeyLock = ''
	local heroicKeyLock = ''
	local accessQuestLock = ''
	local allLocks = ''
	local colour, levelTooLow, levelString, requiredQuestComplete, accessKeyMissing, heroicKeyMissing = Reputable
		:getInstanceInfo(dungeonID, false, nil)
	if accessKeyMissing then accessKeyLock = Reputable:icons('lock', -9) end
	if requiredQuestComplete == false then accessQuestLock = Reputable:icons('lock', -9) end
	allLocks = " " .. levelLock .. accessKeyLock .. accessQuestLock
	if showNormal then
		addLineToHTML(thisPage, "p",
			pre .. Reputable:createLink("instance", dungeonID, false, nil, icon, nil) .. allLocks .. post, true, nil)
	end
	if d.heroic and showHeroic then
		local colour, levelTooLow, levelString, requiredQuestComplete, accessKeyMissing, heroicKeyMissing = Reputable
			:getInstanceInfo(dungeonID, true, nil)
		if heroicKeyMissing then heroicKeyLock = Reputable:icons('lock', -9) end
		allLocks = " " .. levelLock .. heroicKeyLock .. accessKeyLock .. accessQuestLock
		if d.accessKey and thisPage.pagetype ~= "attunement" then
			Reputable:tryMakeItemLink(d.accessKey, thisPage.name, "right", thisPage.i, true, nil, nil)
			thisPage.iRight = thisPage.i
		end
		addLineToHTML(thisPage, "p",
			pre .. Reputable:createLink("instance", dungeonID, true, nil, icon, nil) .. allLocks .. post, true, nil)
	end
end

local function makeDungeonHTMLlist(cat, zoneInfo)
	local thisPage = Reputable.guiTabs[cat].html
	local factionID = zoneInfo.faction
	if type(factionID) == 'table' then factionID = zoneInfo.faction[playerFaction] end
	local factionPage = false
	if Reputable.guiTabs["faction" .. factionID] then factionPage = Reputable.guiTabs["faction" .. factionID].html end
	local factionLink = Reputable:createLink("faction", factionID, nil, nil, nil, nil)
	local heroicKey = zoneInfo.heroicKey
	if heroicKey then
		if type(heroicKey) == 'table' then heroicKey = heroicKey[playerFaction] end
		Reputable:tryMakeItemLink(heroicKey, cat, "right", thisPage.i, true, nil, nil)
		thisPage.iRight = thisPage.i
		if factionPage then
			Reputable:tryMakeItemLink(heroicKey, factionPage.name, "right", factionPage.i, true, nil, nil)
			factionPage.iRight = factionPage.i
		end
	end
	if factionPage then
		addLineToHTML(factionPage, "p",
			Reputable.instanceZones[Reputable.factionInfo[factionID].iz].name .. " " .. factionLink, nil, nil)
	end
	addLineToHTML(Reputable.guiTabs[cat].html, "p", zoneInfo.name .. " " .. factionLink, nil, nil)
	for _, dungeonID in ipairs(zoneInfo.dungeons) do
		Reputable:getInstanceStatus(dungeonID)
		addDungeonToHTML(thisPage, dungeonID, 2, nil, nil)
		if factionPage then addDungeonToHTML(factionPage, dungeonID, 2, nil, nil) end
	end
	if factionPage then addLineToHTML(factionPage, "p", "<br/>", nil, nil) end
	addLineToHTML(Reputable.guiTabs[zoneInfo.cat].html, "p", "<br/>", nil, nil)
end

local function addQuestToHTML(page, questID, repInc, factionID, showLocation)
	local q = Reputable.questInfo[questID]
	if q then
		if q[2] ~= Reputable.notFactionInt[playerFaction] then
			--	if q[2] ~= Reputable.notFactionInt[ playerFaction ] or debug() then
			local levelColor, complete, inProgress, progressIcon, levelMin, levelTooLow, levelString, minF, minR, maxF, maxR, repTooLow, repTooHigh, requiredQuestComplete =
				Reputable:getQuestInfo(questID, nil, factionID)
			local extraInfo = Reputable.extraQuestInfo[questID]
			local repStr = ""
			local repstringColour = "|cFF8080FF"
			if Reputable.ingoredQuestsForRep and Reputable.ingoredQuestsForRep[questID] then
				repstringColour =
				"|cff808080"
			end
			if repInc and repInc > 0 then
				repStr = repstringColour ..
					" +" .. Reputable:repWithMultiplier(repInc, nil) .. "|r"
			end
			if extraInfo and extraInfo.item then
				Reputable:tryMakeItemLink(extraInfo.item, page.name, "right", page.i, nil, nil, nil)
				page.iRight = page.i
			end

			local progress = ''
			if inProgress then
				progress = "|cFFCCCCCC •" .. QUEST_TOOLTIP_ACTIVE .. "|r "
			end
			local showThisDaily = true
			if q[13] == 1 then
				if complete then
					progress = "|cFF00FF00 •" .. format(ACHIEVEMENT_META_COMPLETED_DATE, HONOR_TODAY) ..
						"|r "
				end
			end
			if q[12] == 1 then
				if not (Reputable_Data.global.guiShowExaltedDailies or not repTooHigh) then
					showThisDaily = false
				end
			end

			if page.name == "dailies" then
				if showThisDaily then
					if factionID and not page.dailyFactionHeader[factionID] then
						page.dailyFactionHeader[factionID] = true
						addLineToHTML(page, "p", "<br/>", nil, nil)
						local reputationString = Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions
							[factionID])
						addLineToHTML(page, "p",
							Reputable:createLink("faction", factionID, nil, nil, nil, nil) .. " " .. reputationString,
							nil, nil)
					end
				end
			end

			if showLocation then
				local locationColour = "|cffffffff"
				if complete then locationColour = "|cff808080" end
				--	repStr = locationColour .. ( C_Map.GetAreaInfo( q[6] ) or "" ) .."|r"

				page.right[page.i] = locationColour .. (C_Map.GetAreaInfo(q[6]) or "") .. "|r"
				page.iRight = page.i
				--if debug() then repStr = questID.."||"..q[2].."||".. repStr end
			end

			if showThisDaily and (Reputable_Data.global.guiShowCompletedQuests or not complete) then
				--	if debug() then repStr = repStr.." || "..q[6] end
				addLineToHTML(page, "p",
					Reputable:icons(progressIcon, -9) ..
					" " .. Reputable:createLink("quest", questID, nil, nil, nil, factionID, -8) .. repStr .. progress,
					true, nil)
				page.lastWasHeader = false
			end
		end
	else
		debug("Quest " .. questID .. " missing from questDB")
	end
end

local function addPlayerToDailiesPage(key, show)
	if show then
		local k = Reputable_Data[key]
		if k.profile and server == k.profile.server then
			local color = "|c" .. RAID_CLASS_COLORS[k.profile.class].colorStr
			local dailyCount, dailyList = Reputable:getDailyCount(key)
			--	if dailyList ~= "" then debug( key, dailyList ) end
			if dailyCount > 0 or key == Reputable.profileKey then
				local line = "|cffffff00(" ..
					dailyCount .. " / " .. GetMaxDailyQuests() .. ")|r " .. color .. k.profile.name .. "|r"
				--	if dailyList ~= "" then line = "|Hreputable:dailiesList:"..key.."|h"..line.."|h" end
				line = "|Hreputable:dailiesList:" .. key .. "|h" .. line .. "|h"
				addLineToHTML(Reputable.guiTabs["dailies"].html, "p", line, true, nil)
			end
		end
	end
end

local function makeDataForAllPages()
	for _, htmlObj in pairs(Reputable.guiTabs) do
		if htmlObj.html then
			htmlObj.html.i = 1
			htmlObj.html.right = {}
			htmlObj.html.iRight = 3
		end
		--	if htmlObj.right then
		--	htmlObj.html.i = 1
		--	end
	end
	debug("makeDataForAllPages() fired")
	for _, zoneInfo in ipairs(Reputable.instanceZones) do
		--Reputable.guiTabs[ zoneInfo.cat ].html
		makeDungeonHTMLlist(zoneInfo.cat, zoneInfo)
	end
	local dailiesPage = Reputable.guiTabs["dailies"].html
	dailiesPage.dailyFactionHeader = {}

	if GetDailyQuestsCompleted() >= GetMaxDailyQuests() then
		addLineToHTML(dailiesPage, "p", "|cFFFF0000" .. NO_DAILY_QUESTS_REMAINING .. "|r", nil, nil)
	end

	local timestamp = time() + GetQuestResetTime() + 1
	if not Reputable_Data.global.guiUseLocalTime then
		local st = C_DateAndTime.GetCurrentCalendarTime() -- server
		st.day = st.monthDay
		st.min = st.minute
		timestamp = math.floor((time(st) + GetQuestResetTime() + 1) / 3600 + 0.5) * 3600
	end

	Reputable.guiTabs["dailies"].html.right[1] = DAILY .. " " .. RESET ..
		" " .. date(TIMESTAMP_FORMAT_HHMM_AMPM, timestamp)
	if Reputable_Data.global.dailyDungeons[server].dailyChangeOffset ~= 0 then
		Reputable.guiTabs["dailies"].html.right[2] = DAILY ..
			" " ..
			COMMUNITIES_CREATE_DIALOG_ICON_SELECTION_BUTTON ..
			" " ..
			date(TIMESTAMP_FORMAT_HHMM_AMPM,
				timestamp + 3600 * Reputable_Data.global.dailyDungeons[server].dailyChangeOffset)
	end

	addPlayerToDailiesPage(Reputable.profileKey,
		Reputable_Data.global.ttShowCurrentInList and Reputable_Data.global.profileKeys[Reputable.profileKey])
	if Reputable_Data.global.ttShowList then
		for key, show in pairs(Reputable_Data.global.profileKeys) do
			if key ~= Reputable.profileKey then
				addPlayerToDailiesPage(key, show)
			end
		end
		--GameTooltip:AddLine( " " )
	end
	addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)

	--	guiShowFishingDaily = true,
	--	guiShowCookingDaily = true,
	--	guiShowNormalDaily = true,
	--	guiShowHeroicDaily = true,

	if Reputable_Data.global.guiShowNormalDaily then
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. LFG_TYPE_DAILY_DUNGEON .. "|r", nil, nil)
		if Reputable_Data.global.dailyDungeons[server].dailyNormalDungeon then
			addDungeonToHTML(dailiesPage,
				Reputable.dailyInfo[Reputable_Data.global.dailyDungeons[server].dailyNormalDungeon].instanceID, 0, nil,
				nil)
			addQuestToHTML(dailiesPage, Reputable_Data.global.dailyDungeons[server].dailyNormalDungeon, nil, nil)
		else
			addLineToHTML(dailiesPage, "p",
				"|cff808080[ " .. UNKNOWN .. " - Speak with Nether-Stalker Mah'duun in Shattrath City ]|r", true, nil)
		end
		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	end

	if Reputable_Data.global.guiShowHeroicDaily then
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. LFG_TYPE_DAILY_HEROIC_DUNGEON .. "|r", nil, nil)
		if Reputable_Data.global.dailyDungeons[server].dailyHeroicDungeon then
			addDungeonToHTML(dailiesPage,
				Reputable.dailyInfo[Reputable_Data.global.dailyDungeons[server].dailyHeroicDungeon].instanceID, 1, nil,
				nil)
			addQuestToHTML(dailiesPage, Reputable_Data.global.dailyDungeons[server].dailyHeroicDungeon, nil, nil)
		else
			addLineToHTML(dailiesPage, "p",
				"|cff808080[ " .. UNKNOWN .. " - Speak with Wind Trader Zhareem in Shattrath City ]|r", true, nil)
		end
		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	end

	if Reputable_Data.global.guiShowCookingDaily then
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. PROFESSIONS_COOKING .. " " .. DAILY .. "|r", nil, nil)
		if Reputable_Data.global.dailyDungeons[server].dailyCookingQuest then
			addQuestToHTML(dailiesPage, Reputable_Data.global.dailyDungeons[server].dailyCookingQuest, nil, nil)
		else
			addLineToHTML(dailiesPage, "p", "|cff808080[ " .. UNKNOWN .. " - Speak with The Rokk in Shattrath City ]|r",
				true, nil)
		end
		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	end

	if Reputable_Data.global.guiShowFishingDaily then
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. PROFESSIONS_FISHING .. " " .. DAILY .. "|r", nil, nil)
		if Reputable_Data.global.dailyDungeons[server].dailyFishingQuest then
			addQuestToHTML(dailiesPage, Reputable_Data.global.dailyDungeons[server].dailyFishingQuest, nil, nil)
		else
			addLineToHTML(dailiesPage, "p", "|cff808080[ " ..
				UNKNOWN .. " - Speak with Old Man Barlo in Terokkar Forest ]|r", true, nil)
		end
		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	end

	if Reputable_Data.global.guiShowPvPDaily then
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. PVP .. " " .. DAILY .. "|r", nil, nil)
		if Reputable_Data.global.dailyDungeons[server].dailyPvPQuest then
			addQuestToHTML(dailiesPage, Reputable_Data.global.dailyDungeons[server].dailyPvPQuest, nil, nil)
		else
			if playerFaction == 'Alliance' then
				addLineToHTML(dailiesPage, "p",
					"|cff808080[ " .. UNKNOWN .. " - Speak with an Alliance Brigadier General ]|r", true, nil)
			else
				addLineToHTML(dailiesPage, "p", "|cff808080[ " .. UNKNOWN .. " - Speak with a Horde Warbringer ]|r", true,
					nil)
			end
		end
		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	end

	for _, v in ipairs(Reputable.guiTabs) do
		if v.faction and Reputable.factionInfo[v.faction][playerFaction] ~= false then
			local reputationString = Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions[v.faction])
			local title = REPUTATION ..
				" " .. Reputable:createLink("faction", v.faction, nil, nil, nil, nil) .. " " .. reputationString
			local factionPage = Reputable.guiTabs[v.name].html
			factionPage.header = "<html><body text='#FFFFFF'><h1 align='center'>" .. title .. "</h1><br/>"
			--	local label = Reputable.guiTabs[ Reputable.guiTabs[ v.name ].num ].label

			if Reputable_Data[Reputable.profileKey].factions[v.faction] and Reputable_Data[Reputable.profileKey].factions[v.faction] >= 42000 then
				--label = "|cff00FF00"..label
				Reputable.gui.menu["menuBTN_" .. v.name]:SetNormalFontObject("GameFontGreenSmall")
			end

			if v.faction == 933 then
				local consortiumStanding = Reputable_Data[Reputable.profileKey].factions[933] or 0
				addLineToHTML(factionPage, "h2", CALENDAR_REPEAT_MONTHLY .. " " .. SCENARIO_BONUS_REWARD, nil, nil)
				--addLineToHTML( factionPage, "h2", consortiumStanding, nil, nil )
				if consortiumStanding >= 42000 then
					addQuestToHTML(factionPage, 9887, nil, nil, nil, nil) -- e
				elseif consortiumStanding >= 21000 then
					addQuestToHTML(factionPage, 9885, nil, nil, nil, nil) -- r
				elseif consortiumStanding >= 9000 then
					addQuestToHTML(factionPage, 9884, nil, nil, nil, nil) -- h
				else
					addQuestToHTML(factionPage, 9886, nil, nil, nil, nil) -- f
				end
				addLineToHTML(factionPage, "p", "<br/>", nil, nil)
			end

			if Reputable.factionInfo[v.faction].rquests then
				if Reputable_Data.global.guiShowExaltedDailies or not Reputable_Data[Reputable.profileKey].factions[v.faction] or Reputable_Data[Reputable.profileKey].factions[v.faction] < 42000 then
					addLineToHTML(factionPage, "h2", "Repeatable " .. QUESTS_COLON, nil, nil)
					for _, questID in ipairs(Reputable.factionInfo[v.faction].rquests) do
						local q = Reputable.questInfo[questID]
						if q then
							local repInc = 0
							if v.faction == q[5][1] then
								repInc = q[5][2]
							elseif v.faction == q[5][3] then
								repInc = q[5]
									[4]
							end
							addQuestToHTML(factionPage, questID, repInc, v.faction, nil, nil)
						else
							debug("Repeatable quest missing from questDB", questID)
						end
					end
					addLineToHTML(factionPage, "p", "<br/>", nil, nil)
				end
			end
			if Reputable.questByFaction[v.faction] then
				factionPage.questCounter = { factionPage.i, 0, 0, 0, 0 }
				factionPage.i = factionPage.i + 1
				for _, chain in ipairs(Reputable.questByFaction[v.faction]) do
					if type(chain) == 'string' then
						if factionPage.lastWasHeader then factionPage.i = factionPage.i - 1 end
						factionPage.lastWasHeader = true
						addLineToHTML(factionPage, "h2", chain .. " " .. QUESTS_COLON, nil, nil)
					else
						for _, questID in ipairs(chain) do
							local levelColor, complete, inProgress, progressIcon, levelMin, levelTooLow, levelString, minF, minR, maxF, maxR, repTooLow, repTooHigh, requiredQuestComplete =
								Reputable:getQuestInfo(questID, nil, nil)
							local q = Reputable.questInfo[questID]
							if q then
								if Reputable.questInfo[questID][2] ~= Reputable.notFactionInt[playerFaction] then
									local ingoredQuestForRep = (Reputable.ingoredQuestsForRep and Reputable.ingoredQuestsForRep[questID]) or
										false
									--	if ingoredQuestForRep then debug( questID, ingoredQuestForRep ) end
									local repInc = 0
									if v.faction == q[5][1] then
										repInc = q[5][2]
									elseif v.faction == q[5][3] then
										repInc =
											q[5][4]
									end
									if (q[12] ~= 1 or requiredQuestComplete == false) and not repTooHigh then
										addQuestToHTML(factionPage, questID, repInc, v.faction, nil, nil)
									end
									if q[12] ~= 1 and not repTooHigh and not ingoredQuestForRep then
										factionPage.questCounter[3] = factionPage.questCounter[3] + 1
										factionPage.questCounter[5] = factionPage.questCounter[5] + repInc
										if complete then
											factionPage.questCounter[2] = factionPage.questCounter[2] + 1
											factionPage.questCounter[4] = factionPage.questCounter[4] + repInc
										end
									end

									if q[13] == 1 then
										addQuestToHTML(dailiesPage, questID, repInc, v.faction, nil, nil)
									end
								end
							else
								debug("Quest missing from questDB", questID)
							end
						end
					end
				end
				local counterStr = REPUTATION .. " " .. QUEST_LOG_COUNT
				counterStr = string.gsub(counterStr, "%%d", factionPage.questCounter[2], 1)
				counterStr = string.gsub(counterStr, "%%d", factionPage.questCounter[3], 1)
				local remainingRep = factionPage.questCounter[5] - factionPage.questCounter[4]
				local remainingRepStr = ""
				if remainingRep > 0 then
					if Reputable_Data[Reputable.profileKey].factions[v.faction] then
						remainingRepStr = " => " ..
							Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions[v.faction] +
								remainingRep)
					else
						remainingRepStr = AVAILABLE ..
							": |cFF8080FF" .. Reputable:repWithMultiplier(remainingRep, nil) .. "|r"
					end
				end
				local counterRepStr = " |cFF8080FF ( " ..
					Reputable:repWithMultiplier(factionPage.questCounter[4], nil) ..
					" / " .. Reputable:repWithMultiplier(factionPage.questCounter[5], nil) .. " )|r " .. remainingRepStr
				addLineToHTML(factionPage, "h2", counterStr .. counterRepStr, false, factionPage.questCounter[1])
				addLineToHTML(factionPage, "p", "<br/>", nil, nil)
				addLineToHTML(factionPage, "p", "<br/>", nil, nil)

				if factionPage.questCounter[2] == factionPage.questCounter[3] then
					--label = label..Reputable:icons( 'tick' )
					local label = Reputable.guiTabs[Reputable.guiTabs[v.name].num].label .. Reputable:icons('tick')
					Reputable.gui.menu["menuBTN_" .. v.name]:SetText(label)
				end
				--Reputable.gui.menu[ "menuBTN_" .. v.name ]:SetText(label)
			end
		end
	end


	for attunementID, data in pairs(Reputable.attunements) do
		local pageName = "attune" .. attunementID
		local page = Reputable.guiTabs[pageName].html
		local attunementComplete = false
		if data.check then
			if data.check.item then
				if GetItemCount(data.check.item, true) > 0 then
					attunementComplete = true
				end
			end
			if data.check.quest then
				if type(data.check.quest) == 'table' then
					for _, thisQuestCheck in pairs(data.check.quest) do
						if C_QuestLog.IsQuestFlaggedCompleted(thisQuestCheck) then attunementComplete = true end
					end
				else
					attunementComplete = C_QuestLog.IsQuestFlaggedCompleted(data.check.quest)
				end
			end
		end
		if attunementComplete then
			local label = Reputable.guiTabs[Reputable.guiTabs[pageName].num].label
			Reputable.gui.menu["menuBTN_" .. pageName]:SetText("|cff00FF00" .. label .. Reputable:icons('tick'))
			page.header = "<html><body text='#FFFFFF'><h1 align='center'>" ..
				label .. " (|cff00FF00" .. COMPLETE .. "|r)</h1><br/>"
		end
		if not attunementComplete or Reputable_Data.global.guiShowCompletedQuests then
			if data.requirements then
				if data.requirements.reputation then
					addLineToHTML(page, "p", string.gsub(LOCKED_WITH_ITEM, "%%s", REPUTATION .. ":"), nil, nil)
					for _, reputation in ipairs(data.requirements.reputation) do
						local factionName = GetFactionInfoByID(reputation[1])
						if not factionName then
							if Reputable.factionInfo[reputation[1]] then
								factionName = Reputable.factionInfo
									[reputation[1]].name
							else
								factionName = "Unknown Faction"
							end
						end
						--Reputable_Data[Reputable.profileKey].factions[reputation[1]]
						local _, _, _, repReqStr = Reputable:getRepString(reputation[2])
						local meetsRepRequirement = Reputable:icons(
							Reputable_Data[Reputable.profileKey].factions[reputation[1]] ~= nil and
							Reputable_Data[Reputable.profileKey].factions[reputation[1]] >= reputation[2], -8)
						repReqStr = factionName .. " " .. repReqStr .. " " .. meetsRepRequirement .. " "
						local currentRepStr = ""
						if Reputable_Data[Reputable.profileKey].factions[reputation[1]] then
							currentRepStr = Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions
								[reputation[1]])
						end
						addLineToHTML(page, "p",
							"|cFF8080FF|Hreputable:faction:" ..
							reputation[1] .. "|h" .. repReqStr .. currentRepStr .. "|h|r", true, nil)
					end
					addLineToHTML(page, "p", "<br/>", nil, nil)
				end
				if data.requirements.dungeons then
					addLineToHTML(page, "p", string.gsub(LOCKED_WITH_ITEM, "%%s", DUNGEONS .. ":"), nil, nil)
					for _, dungeon in ipairs(data.requirements.dungeons) do
						addDungeonToHTML(page, dungeon[1], dungeon[2], nil, nil)
					end
					addLineToHTML(page, "p", "<br/>", nil, nil)
				end
				if data.requirements.items then
					addLineToHTML(page, "p", string.gsub(LOCKED_WITH_ITEM, "%%s", ITEMS .. ":"), nil, nil)
					for _, item in ipairs(data.requirements.items) do
						Reputable:tryMakeItemLink(item[1], pageName, "tab", page.i, false, "", "|cffffd100 x" .. item[2])
					end
					addLineToHTML(page, "p", "<br/>", nil, nil)
				end
			end
			if data.chain then
				addLineToHTML(page, "p", "Attunement:", nil, nil)
				local pieceStart = page.i
				for _, piece in ipairs(data.chain) do
					if type(piece) == 'number' then
						addQuestToHTML(page, piece, nil, nil)
					elseif type(piece) == 'string' then

					elseif piece[1] ~= Reputable.notFactionInt[playerFaction] then
						local bitStart = page.i
						local bitComplete = false
						for i, bit in ipairs(piece) do
							local first
							if i == 1 then first = true end
							if piece[i - 1] == 1 or piece[i - 1] == 2 then first = true end
							if bit ~= Reputable.factionInt[playerFaction] then
								if first and pieceStart ~= bitStart then addLineToHTML(page, "p", "<br/>", nil, nil) end
								if type(bit) == 'number' then
									if Reputable_Data[Reputable.profileKey].quests[bit] == true then bitComplete = true end
									addQuestToHTML(page, bit, nil, nil)
								else
									local stepType = bit:sub(1, 1)
									local stepNumber = bit:sub(2)
									local step
									if stepType == 'n' then
									elseif stepType == 'i' then
										local difficulty = tonumber(stepNumber:sub(1, 1))
										local difficultyType = LFG_TYPE_DUNGEON
										if difficulty == 2 then
											difficulty = 0
											--		difficultyType = CHAT_MSG_INSTANCE_CHAT
										end
										addDungeonToHTML(page, tonumber(stepNumber:sub(2)), difficulty,
											difficultyType .. ": ", nil)
									elseif stepType == 'a' then
										if playerFaction == 'Alliance' then step = stepNumber end
									elseif stepType == 'h' then
										if playerFaction == 'Horde' then step = stepNumber end
									else
										step = bit
									end
									if step then addLineToHTML(page, "h2", "|cffffd100 " .. step, true, nil) end
								end
							end
						end
						if bitComplete and not Reputable_Data.global.guiShowCompletedQuests then page.i = bitStart end
					end
				end
				addLineToHTML(page, "p", "<br/>", nil, nil)
				addLineToHTML(page, "p", "<br/>", nil, nil)
			end
		else
			addLineToHTML(page, "p", SPLASH_BOOST_HEADER, true, nil)
		end
	end

	if Reputable.brewfest then
		local pageName = Reputable.guiTabs["brewfest"].html
		Reputable.brewfestCurrencyBags = GetItemCount(37829)
		Reputable.brewfestCurrencyTotal = GetItemCount(37829, true)
		local currencyString = "|cffffff00" .. Reputable.brewfestCurrencyTotal
		if Reputable.brewfestCurrencyTotal > Reputable.brewfestCurrencyBags then
			currencyString = currencyString ..
				" (" ..
				INVTYPE_BAG ..
				": " ..
				Reputable.brewfestCurrencyBags ..
				", " .. BANK .. ": " .. Reputable.brewfestCurrencyTotal - Reputable.brewfestCurrencyBags .. ")"
		end
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		Reputable:tryMakeItemLink(37829, pageName.name, "right", pageName.i, nil, nil, nil); pageName.iRight = pageName
			.i
		addLineToHTML(pageName, "p", BATTLE_PET_SOURCE_7 .. " " .. CURRENCY .. ": " .. currencyString .. "|r", nil, nil)
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		addLineToHTML(pageName, "h2", "Repeatable " .. QUESTS_COLON, nil, nil)

		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. BATTLE_PET_SOURCE_7 .. ": Brewfest|r", nil, nil)
		for _, questID in ipairs(Reputable.questByGroup["Brewfest"].dailies) do
			addQuestToHTML(pageName, questID, nil, nil)
			addQuestToHTML(dailiesPage, questID, nil, nil)
		end

		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		for _, chain in ipairs(Reputable.questByGroup["Brewfest"].quests) do
			if type(chain) == 'string' then
				if pageName.lastWasHeader then pageName.i = pageName.i - 1 end
				pageName.lastWasHeader = true
				local header = ""
				local stepType, stepValue, stepDefault = strsplit(":", chain)
				if stepType == 'm' then
					header = (C_Map.GetAreaInfo(stepValue) or stepDefault) .. ":"
				else
					header = chain ..
						":"
				end
				addLineToHTML(pageName, "h2", header, nil, nil)
			else
				for _, questID in ipairs(chain) do
					local levelColor, complete, inProgress, progressIcon, levelMin, levelTooLow, levelString, minF, minR, maxF, maxR, repTooLow, repTooHigh, requiredQuestComplete =
						Reputable:getQuestInfo(questID, nil, nil)
					local q = Reputable.questInfo[questID]
					if q then
						if Reputable.questInfo[questID][2] ~= Reputable.notFactionInt[playerFaction] then
							if (q[12] ~= 1 or requiredQuestComplete == false) and not repTooHigh then
								addQuestToHTML(pageName, questID, nil, nil, true)
							end
						end
					else
						debug("Quest missing from questDB", questID)
					end
				end
			end
		end
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
	end

	if Reputable.midsummer then
		local pageName = Reputable.guiTabs["midsummer"].html
		Reputable.midsummerCurrencyBags = GetItemCount(23247)
		Reputable.midsummerCurrencyTotal = GetItemCount(23247, true)
		local currencyString = "|cffffff00" .. Reputable.midsummerCurrencyTotal
		if Reputable.midsummerCurrencyTotal > Reputable.midsummerCurrencyBags then
			currencyString = currencyString ..
				" (" ..
				INVTYPE_BAG ..
				": " ..
				Reputable.midsummerCurrencyBags ..
				", " .. BANK .. ": " .. Reputable.midsummerCurrencyTotal - Reputable.midsummerCurrencyBags .. ")"
		end
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		Reputable:tryMakeItemLink(23247, pageName.name, "right", pageName.i, nil, nil, nil); pageName.iRight = pageName
			.i
		addLineToHTML(pageName, "p", BATTLE_PET_SOURCE_7 .. " " .. CURRENCY .. ": " .. currencyString .. "|r", nil, nil)
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		addLineToHTML(pageName, "h2", "Repeatable " .. QUESTS_COLON, nil, nil)

		addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
		addLineToHTML(dailiesPage, "p", "|cffffff00" .. BATTLE_PET_SOURCE_7 .. ": Midsummer Fire Festival|r", nil, nil)
		for _, questID in ipairs(Reputable.questByGroup["Midsummer_fire_festival"].dailies) do
			if questID == 11954 then
				if level >= 65 then
				elseif level >= 54 then
					questID = 11953
				elseif level >= 45 then
					questID = 11952
				elseif level >= 39 then
					questID = 11948
				elseif level >= 26 then
					questID = 11947
				else
					questID = 11917
				end
			end
			addQuestToHTML(pageName, questID, nil, nil)
			addQuestToHTML(dailiesPage, questID, nil, nil)
		end

		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		for _, chain in ipairs(Reputable.questByGroup["Midsummer_fire_festival"].quests) do
			if type(chain) == 'string' then
				if pageName.lastWasHeader then pageName.i = pageName.i - 1 end
				pageName.lastWasHeader = true
				local header = ""
				local stepType, stepValue, stepDefault = strsplit(":", chain)
				if stepType == 'm' then
					header = (C_Map.GetAreaInfo(stepValue) or stepDefault) .. ":"
				else
					header = chain ..
						":"
				end
				addLineToHTML(pageName, "h2", header, nil, nil)
			else
				for _, questID in ipairs(chain) do
					if questID == 11954 then
						if level >= 65 then
						elseif level >= 54 then
							questID = 11953
						elseif level >= 45 then
							questID = 11952
						elseif level >= 39 then
							questID = 11948
						elseif level >= 26 then
							questID = 11947
						else
							questID = 11917
						end
					end
					local levelColor, complete, inProgress, progressIcon, levelMin, levelTooLow, levelString, minF, minR, maxF, maxR, repTooLow, repTooHigh, requiredQuestComplete =
						Reputable:getQuestInfo(questID, nil, nil)
					local q = Reputable.questInfo[questID]
					if q then
						if Reputable.questInfo[questID][2] ~= Reputable.notFactionInt[playerFaction] then
							if (q[12] ~= 1 or requiredQuestComplete == false) and not repTooHigh then
								addQuestToHTML(pageName, questID, nil, nil, true)
							end
						end
					else
						debug("Quest missing from questDB", questID)
					end
				end
			end
		end
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
		addLineToHTML(pageName, "p", "<br/>", nil, nil)
	end

	addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)
	addLineToHTML(dailiesPage, "p", "<br/>", nil, nil)

	--classicFactionPages
	for questID in pairs(Reputable.questInfo) do
		-- Never abort building all pages because one quest is ignored.
		-- (The original code used 'return' here, which can result in an empty UI.)
		if Reputable.questIgnore[questID] then
			-- skip
		else
			local q = Reputable.questInfo[questID]
			local repIncrease = q[5][2]
			if q[12] ~= 1 and q[6] > 0 then
				if classicFactionPages[q[5][1]] then
					addQuestToHTML(Reputable.guiTabs["faction" .. q[5][1]].html, questID, repIncrease, nil, true)
				elseif q[5][1] == 67 then -- Horde
					addQuestToHTML(Reputable.guiTabs["faction911"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction76"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction530"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction68"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction81"].html, questID, repIncrease, nil, true)
				elseif q[5][1] == 469 then -- Alliance
					addQuestToHTML(Reputable.guiTabs["faction930"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction69"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction72"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction47"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction54"].html, questID, repIncrease, nil, true)
				elseif q[5][1] == 169 then -- Steamwheedle Cartel
					addQuestToHTML(Reputable.guiTabs["faction21"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction577"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction369"].html, questID, repIncrease, nil, true)
					addQuestToHTML(Reputable.guiTabs["faction470"].html, questID, repIncrease, nil, true)
				end
			end
		end
	end
	for f in pairs(classicFactionPages) do
		if Reputable_Data[Reputable.profileKey].factions[f] and Reputable_Data[Reputable.profileKey].factions[f] >= 42000 then
			Reputable.gui.menu["menuBTN_" .. "faction" .. f]:SetNormalFontObject("GameFontGreenSmall")
		end
		addLineToHTML(Reputable.guiTabs["faction" .. f].html, "p", "<br/>", nil, nil)
		addLineToHTML(Reputable.guiTabs["faction" .. f].html, "p", "<br/>", nil, nil)
	end

	Reputable.guiNeedsUpdate = false
end

local function createGUI(page)
	local menuW = 160

	local function StripHTMLBackground(html)
		if not html or not html.GetRegions then return end
		for _, region in ipairs({ html:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == "Texture" then
				region:SetTexture(nil)
				region:Hide()
			end
		end
	end

	-- SimpleHTML:SetFont differs between client eras.
	-- Older: html:SetFont(fontFile, height, flags)
	-- Newer: html:SetFont(textType, fontFile, height, flags)
	local function setHTMLFont(html, fontFile, height, flags)
		if not html or not html.SetFont then return end
		-- Try old signature first.
		local ok = pcall(html.SetFont, html, fontFile, height, flags)
		if ok then return end
		-- Newer signature: set at least paragraph and common headings.
		pcall(html.SetFont, html, "p", fontFile, height, flags)
		pcall(html.SetFont, html, "h1", fontFile, height + 6, flags)
		pcall(html.SetFont, html, "h2", fontFile, height + 4, flags)
		pcall(html.SetFont, html, "h3", fontFile, height + 2, flags)
	end

	-- SimpleHTML:SetSpacing differs between client eras.
	-- Older: html:SetSpacing(spacing)
	-- Newer: html:SetSpacing(textType, spacing)
	local function setHTMLSpacing(html, spacing)
		if not html or not html.SetSpacing then return end
		local ok = pcall(html.SetSpacing, html, spacing)
		if ok then return end
		pcall(html.SetSpacing, html, "p", spacing)
		pcall(html.SetSpacing, html, "h1", spacing)
		pcall(html.SetSpacing, html, "h2", spacing)
		pcall(html.SetSpacing, html, "h3", spacing)
	end

	Reputable.gui = CreateFrame("frame", "ReputableGUI", UIParent, BackdropTemplateMixin and "BackdropTemplate");
	local cont = Reputable.gui
	cont.useTextRenderer = true
	cont:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = 1,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	cont:SetWidth(800)
	cont:SetHeight(420)
	cont:SetPoint("CENTER", UIParent)
	cont:EnableMouse(true)
	cont:SetMovable(true)
	cont:SetClampedToScreen(true)
	cont:SetResizable(true)
	if cont.SetMinResize then
		cont:SetMinResize(400, 120)
	else
		cont.__repMinW, cont.__repMinH = 400, 120
		local __repSizing
		cont:HookScript("OnSizeChanged", function(self, w, h)
			if __repSizing then return end
			local mw, mh = self.__repMinW, self.__repMinH
			if not mw or not mh then return end
			__repSizing = true
			if w and w < mw then self:SetWidth(mw) end
			if h and h < mh then self:SetHeight(mh) end
			__repSizing = false
		end)
	end
	cont:RegisterForDrag("LeftButton")
	cont:SetScript("OnDragStart", function(self) self:StartMoving() end)
	cont:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	cont:SetFrameStrata("FULLSCREEN_DIALOG")
	tinsert(UISpecialFrames, "ReputableGUI")

	cont.closeBTN = CreateFrame("button", "", cont, "UIPanelButtonTemplate")
	cont.closeBTN:SetHeight(24)
	cont.closeBTN:SetWidth(26)
	cont.closeBTN:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -5, -5)
	cont.closeBTN:SetText("X")
	cont.closeBTN:SetScript("OnClick", function(self) cont:Hide() end)

	cont.settingsBTN = CreateFrame("button", "", cont, "UIPanelButtonTemplate")
	cont.settingsBTN:SetHeight(24)
	cont.settingsBTN:SetWidth(80)
	cont.settingsBTN:SetPoint("RIGHT", cont.closeBTN, "LEFT", 0, 0)
	cont.settingsBTN:SetText(GAMEOPTIONS_MENU)
	cont.settingsBTN:SetScript("OnClick", function()
		cont:Hide(); OpenOptionsCompat()
	end)

	cont.showCompletedQuests = CreateFrame("CheckButton", nil, cont, "UICheckButtonTemplate");
	cont.showCompletedQuests:SetPoint("RIGHT", cont.settingsBTN, "LEFT", 0, -1);
	cont.showCompletedQuests:SetScript("OnEnter",
		function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, -32); GameTooltip:SetText(
				TOOLTIP_TRACKER_FILTER_COMPLETED_QUESTS); GameTooltip:Show()
		end)
	cont.showCompletedQuests:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
	if Reputable_Data.global.guiShowCompletedQuests then cont.showCompletedQuests:SetChecked(true) end
	cont.showCompletedQuests:SetScript("OnClick",
		function()
			Reputable_Data.global.guiShowCompletedQuests = cont.showCompletedQuests:GetChecked()
			Reputable:guiUpdate(true)
		end);

	cont.showExaltedDailies = CreateFrame("CheckButton", nil, cont, "UICheckButtonTemplate");
	cont.showExaltedDailies:SetPoint("RIGHT", cont.showCompletedQuests, "LEFT", 0, 0);
	cont.showExaltedDailies:SetScript("OnEnter",
		function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, -32); GameTooltip:SetText(SHOW ..
				" " .. FACTION_STANDING_LABEL8 .. " repeatable " .. QUESTS_LABEL); GameTooltip:Show()
		end)
	cont.showExaltedDailies:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
	if Reputable_Data.global.guiShowExaltedDailies then cont.showExaltedDailies:SetChecked(true) end
	cont.showExaltedDailies:SetScript("OnClick",
		function()
			Reputable_Data.global.guiShowExaltedDailies = cont.showExaltedDailies:GetChecked()
			Reputable:guiUpdate(true)
		end);

	cont.resizeBTN = CreateFrame("Button", nil, cont)
	cont.resizeBTN:SetSize(16, 16)
	cont.resizeBTN:SetPoint("BOTTOMRIGHT")
	cont.resizeBTN:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	cont.resizeBTN:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	cont.resizeBTN:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	cont.resizeBTN:SetScript("OnMouseDown", function(self, button)
		cont:StartSizing("BOTTOMRIGHT")
		cont:SetUserPlaced(true)
	end)
	cont.resizeBTN:SetScript("OnMouseUp", function(self, button)
		cont:StopMovingOrSizing()
		local width = cont.scrollFrameMain:GetWidth()
		cont.main:SetWidth(width)
		if Reputable.gui and Reputable.gui.html_right then Reputable.gui.html_right:SetWidth(width - 20) end
		if Reputable.gui and Reputable.gui.html_main then Reputable.gui.html_main:SetWidth(width - 20) end
		if RefreshMainScrollLayout then RefreshMainScrollLayout(false) end
		Reputable:loadHTML(nil)
	end)

	cont.title = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	cont.title:SetText(addonName)
	cont.title:SetPoint("TOPLEFT", 10, -10)

	cont.version = cont:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cont.version:SetText("(v" .. version .. ")")
	cont.version:SetPoint("LEFT", cont.title, "RIGHT", 5, 0)

	cont.author = cont:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cont.author:SetText(string.gsub(PETITION_CREATOR, "%%s", author))
	cont.author:SetPoint("LEFT", cont.version, "RIGHT", 5, 0)

	cont.headerLine = cont:CreateLine()
	cont.headerLine:SetColorTexture(1, 1, 1, 0.5)
	cont.headerLine:SetThickness(1)
	cont.headerLine:SetStartPoint("TOPLEFT", 4, -32)
	cont.headerLine:SetEndPoint("TOPRIGHT", -4, -32)

	cont.menuLine = cont:CreateLine()
	cont.menuLine:SetColorTexture(1, 1, 1, 0.5)
	cont.menuLine:SetThickness(1)
	cont.menuLine:SetStartPoint("TOPLEFT", menuW + 25, -32)
	cont.menuLine:SetEndPoint("BOTTOMLEFT", menuW + 25, 3)

	cont.scrollFrameMenu = CreateFrame("ScrollFrame", "$parent_MenuScrollFrame", cont, "UIPanelScrollFrameTemplate");
	cont.scrollBar = _G[cont.scrollFrameMenu:GetName() .. "ScrollBar"];
	cont.scrollFrameMenu:SetWidth(menuW);
	cont.scrollFrameMenu:SetPoint("TOPLEFT", 0, -35);
	cont.scrollFrameMenu:SetPoint("BOTTOM", 0, 10);

	cont.menu = CreateFrame("Frame", "$parent_MenuScrollChild", cont.scrollFrameMenu);
	cont.menu.y = 0
	-- In some newer clients, ScrollFrame children do not reliably auto-size from anchors.
	-- Explicitly size the scroll child to the visible scroll frame area.
	cont.menu:SetPoint("TOPLEFT", cont.scrollFrameMenu, "TOPLEFT", 0, 0)
	cont.menu:SetSize(menuW, cont.scrollFrameMenu:GetHeight() or 1)
	cont.scrollFrameMenu:SetScrollChild(cont.menu);

	cont.scrollFrameMain = CreateFrame("ScrollFrame", "$parent_MainScrollFrame", cont, "UIPanelScrollFrameTemplate");
	cont.scrollBar = _G[cont.scrollFrameMain:GetName() .. "ScrollBar"];
	cont.scrollFrameMain:SetPoint("TOPLEFT", menuW + 25, -35);
	cont.scrollFrameMain:SetPoint("BOTTOMRIGHT", -30, 10);
	cont.scrollFrameMain:EnableMouseWheel(true)

	cont.main = CreateFrame("Frame", "$parent_MainScrollChild", cont.scrollFrameMain);
	cont.main.y = 0
	cont.main:SetPoint("TOPLEFT", cont.scrollFrameMain, "TOPLEFT", 0, 0)
	cont.main:SetSize(cont.scrollFrameMain:GetWidth() or 1, cont.scrollFrameMain:GetHeight() or 1)
	cont.scrollFrameMain:SetScrollChild(cont.main);
	cont.main:EnableMouseWheel(true)
	cont.mainScrollBar = _G[cont.scrollFrameMain:GetName() .. "ScrollBar"]
	local mainScrollUp = _G[cont.scrollFrameMain:GetName() .. "ScrollBarScrollUpButton"]
	local mainScrollDown = _G[cont.scrollFrameMain:GetName() .. "ScrollBarScrollDownButton"]

	local function SetNativeMainScrollbarVisible(show)
		if cont.mainScrollBar then
			cont.mainScrollBar:SetShown(show)
			cont.mainScrollBar:SetAlpha(show and 1 or 0)
			cont.mainScrollBar:EnableMouse(show)
		end
		if mainScrollUp then
			mainScrollUp:SetShown(show)
			mainScrollUp:EnableMouse(show)
		end
		if mainScrollDown then
			mainScrollDown:SetShown(show)
			mainScrollDown:EnableMouse(show)
		end
	end

	cont.textScroll = CreateFrame("Slider", nil, cont, "UIPanelScrollBarTemplate")
	cont.textScroll:SetPoint("TOPRIGHT", cont.scrollFrameMain, "TOPRIGHT", 16, -16)
	cont.textScroll:SetPoint("BOTTOMRIGHT", cont.scrollFrameMain, "BOTTOMRIGHT", 16, 16)
	cont.textScroll:SetMinMaxValues(0, 0)
	cont.textScroll:SetValueStep(1)
	if cont.textScroll.SetObeyStepOnDrag then cont.textScroll:SetObeyStepOnDrag(true) end
	cont.textScroll:SetOrientation("VERTICAL")
	cont.textScroll:Hide()

	local function SetTextScrollOffset(viewOffset, updateSlider)
		if not Reputable.gui or not Reputable.gui.useTextRenderer then return end
		local maxOffset = cont.__repTextMaxOffset or 0
		viewOffset = math.floor((viewOffset or 0) + 0.5)
		if viewOffset < 0 then viewOffset = 0 end
		if viewOffset > maxOffset then viewOffset = maxOffset end
		cont.__repTextOffset = viewOffset
		-- Convert "view offset" (0 = top of document) to ScrollingMessageFrame
		-- scroll offset (0 = bottom/newest content, max = top/oldest content).
		local smfOffset = maxOffset - viewOffset
		if Reputable.gui.text_main and Reputable.gui.text_main.SetScrollOffset then
			pcall(Reputable.gui.text_main.SetScrollOffset, Reputable.gui.text_main, smfOffset)
		end
		if Reputable.gui.text_right and Reputable.gui.text_right.SetScrollOffset then
			pcall(Reputable.gui.text_right.SetScrollOffset, Reputable.gui.text_right, smfOffset)
		end
		if updateSlider and cont.textScroll then
			cont.textScroll:SetValue(viewOffset)
		end
	end
	cont.textScroll:SetScript("OnValueChanged", function(self, value)
		SetTextScrollOffset(value, false)
	end)

	local function ScrollMain(delta)
		if Reputable.gui and Reputable.gui.useTextRenderer then
			local step = 1
			if IsShiftKeyDown and IsShiftKeyDown() then step = 5 end
			local current = cont.__repTextOffset or 0
			if delta > 0 then
				current = current - step  -- scroll wheel up → towards top of document
			else
				current = current + step  -- scroll wheel down → towards bottom
			end
			SetTextScrollOffset(current, true)
			return
		end

		local viewH = cont.scrollFrameMain:GetHeight() or 1
		local contentH = cont.main:GetHeight() or viewH
		local maxScroll = math.max(0, contentH - viewH)
		if maxScroll <= 0 then
			cont.scrollFrameMain:SetVerticalScroll(0)
			return
		end
		local current = cont.scrollFrameMain:GetVerticalScroll() or 0
		local step = 28
		local nextValue = current - (delta * step)
		if nextValue < 0 then nextValue = 0 end
		if nextValue > maxScroll then nextValue = maxScroll end
		cont.scrollFrameMain:SetVerticalScroll(nextValue)
	end
	cont.scrollFrameMain:SetScript("OnMouseWheel", function(_, delta) ScrollMain(delta) end)
	cont.main:SetScript("OnMouseWheel", function(_, delta) ScrollMain(delta) end)

	-- Layout/sizing (TBC Anniversary UI quirks)
	-- Some builds report 0 sizes during initial construction. We force deterministic
	-- sizes and keep all content top-aligned in a single outer scroll model.
	local function ApplyMainContentHeight(resetToTop)
		local viewH = cont.scrollFrameMain:GetHeight()
		if not viewH or viewH < 1 then viewH = 1 end

		local contentH = viewH
		local gui = Reputable and Reputable.gui
		if gui and gui.useTextRenderer and gui.text_main and gui.text_right then
			local _, fontH = gui.text_main:GetFont()
			if not fontH or fontH < 1 then fontH = 12 end
			local lineH = math.max(14, fontH + 3)
			local leftLines = gui.text_main.__repLineCount or gui.text_main:GetNumMessages() or 1
			local rightLines = gui.text_right.__repLineCount or gui.text_right:GetNumMessages() or 1
			local visibleLines = math.max(1, math.floor(viewH / lineH))
			local totalLines = math.max(leftLines, rightLines)
			local maxOffset = math.max(0, totalLines - visibleLines)
			cont.__repTextMaxOffset = maxOffset
			contentH = viewH
			gui.text_main:SetHeight(viewH)
			gui.text_right:SetHeight(viewH)
			SetNativeMainScrollbarVisible(false)
			if cont.textScroll then
				cont.textScroll:SetMinMaxValues(0, maxOffset)
				cont.textScroll:SetValue(cont.__repTextOffset or 0)
				cont.textScroll:SetShown(maxOffset > 0)
			end
		elseif gui and gui.html_main and gui.html_right then
			local leftH = (gui.html_main.GetContentHeight and gui.html_main:GetContentHeight()) or gui.html_main:GetHeight() or viewH
			local rightH = (gui.html_right.GetContentHeight and gui.html_right:GetContentHeight()) or gui.html_right:GetHeight() or viewH
			local tabH = (gui.html_tab1 and gui.html_tab1.GetContentHeight and gui.html_tab1:GetContentHeight()) or 0
			contentH = math.max(viewH, leftH, rightH, tabH) + 20
			gui.html_main:SetHeight(contentH)
			gui.html_right:SetHeight(contentH)
			if gui.html_tab1 then gui.html_tab1:SetHeight(contentH) end
			if cont.textScroll then cont.textScroll:Hide() end
			SetNativeMainScrollbarVisible(true)
		end

		local width = cont.main:GetWidth() or 1
		cont.main:SetSize(width, contentH)

		local maxScroll = math.max(0, contentH - viewH)
		if resetToTop then
			cont.scrollFrameMain:SetVerticalScroll(0)
			if gui and gui.useTextRenderer then
				SetTextScrollOffset(0, true)
			end
		else
			local current = cont.scrollFrameMain:GetVerticalScroll() or 0
			if current > maxScroll then
				cont.scrollFrameMain:SetVerticalScroll(maxScroll)
			end
			if gui and gui.useTextRenderer then
				SetTextScrollOffset(cont.__repTextOffset or 0, true)
			end
		end
	end
	RefreshMainScrollLayout = ApplyMainContentHeight

	local function ApplyLayout()
		local contW = cont:GetWidth()
		local contH = cont:GetHeight()
		if not contW or contW < 1 then contW = 1 end
		if not contH or contH < 1 then contH = 1 end
		-- Menu viewport (some builds report 0 until shown)
		local mw = cont.scrollFrameMenu:GetWidth()
		local mh = cont.scrollFrameMenu:GetHeight()
		if not mw or mw < 1 then mw = menuW end
		if not mh or mh < 1 then mh = contH - 55 end
		if mh < 1 then mh = 1 end
		-- Ensure the scroll child is tall enough to contain its children.
		local menuChildH = mh
		if cont.menu and type(cont.menu.y) == "number" then
			menuChildH = math.max(mh, (-cont.menu.y) + 40)
		end
		cont.menu:SetSize(mw, menuChildH)
		-- Main viewport
		local w = cont.scrollFrameMain:GetWidth()
		local h = cont.scrollFrameMain:GetHeight()
		if not w or w < 1 then w = contW - (menuW + 25) - 35 end
		if not h or h < 1 then h = contH - 55 end
		if w < 1 then w = 1 end
		if h < 1 then h = 1 end
		cont.main:SetWidth(w)

		-- Layout the text renderer frames (two-column layout, top-aligned)
		local gui = Reputable and Reputable.gui
		if gui and gui.useTextRenderer and gui.text_main and gui.text_right then
			local pad = 16
			local gap = 10
			local rightW = 200
			if w < (pad * 2 + rightW + gap + 50) then
				rightW = math.max(100, math.floor(w * 0.25))
			end

			-- Centered title at the very top
			local titleOffset = 0
			if gui.text_title then
				gui.text_title:ClearAllPoints()
				gui.text_title:SetPoint("TOPLEFT", cont.main, "TOPLEFT", pad, -4)
				gui.text_title:SetPoint("TOPRIGHT", cont.main, "TOPRIGHT", -pad, -4)
				local titleH = gui.text_title:GetStringHeight() or 0
				if titleH > 0 then titleOffset = titleH + 10 end
			end

			gui.text_main:ClearAllPoints()
			gui.text_main:SetPoint("TOPLEFT", cont.main, "TOPLEFT", pad, -titleOffset)
			gui.text_main:SetPoint("TOPRIGHT", cont.main, "TOPRIGHT", -(pad + rightW + gap), -titleOffset)
			gui.text_main:Show()

			gui.text_right:ClearAllPoints()
			gui.text_right:SetPoint("TOPRIGHT", cont.main, "TOPRIGHT", -pad, -titleOffset)
			gui.text_right:SetWidth(rightW)
			gui.text_right:Show()

			if gui.html_main then gui.html_main:Hide() end
			if gui.html_right then gui.html_right:Hide() end
			if gui.html_tab1 then gui.html_tab1:Hide() end
		elseif gui and gui.html_main and gui.html_right then
			local pad = 16
			local gap = 10
			local rightW = 210
			if w < (pad * 2 + rightW + gap + 50) then
				rightW = math.max(130, math.floor(w * 0.30))
			end

			gui.html_main:ClearAllPoints()
			gui.html_main:SetPoint("TOPLEFT", cont.main, "TOPLEFT", pad, 0)
			gui.html_main:SetPoint("TOPRIGHT", cont.main, "TOPRIGHT", -(pad + rightW + gap), 0)
			gui.html_main:SetAlpha(1)
			gui.html_main:Show()

			gui.html_right:ClearAllPoints()
			gui.html_right:SetPoint("TOPRIGHT", cont.main, "TOPRIGHT", -pad, 0)
			gui.html_right:SetWidth(rightW)
			gui.html_right:SetAlpha(1)
			gui.html_right:Show()

			if gui.html_tab1 then
				gui.html_tab1:ClearAllPoints()
				gui.html_tab1:SetPoint("TOPLEFT", gui.html_main, "TOPLEFT", 14, 0)
				gui.html_tab1:SetPoint("TOPRIGHT", gui.html_main, "TOPRIGHT", 0, 0)
				gui.html_tab1:SetAlpha(1)
				gui.html_tab1:Show()
			end

			if gui.text_main then gui.text_main:Hide() end
			if gui.text_right then gui.text_right:Hide() end
			if gui.text_title then gui.text_title:Hide() end
		end

		ApplyMainContentHeight(false)
	end

	cont:HookScript("OnShow", ApplyLayout)
	cont.scrollFrameMenu:HookScript("OnSizeChanged", ApplyLayout)
	cont.scrollFrameMain:HookScript("OnSizeChanged", ApplyLayout)
	cont:HookScript("OnSizeChanged", ApplyLayout)
	-- Run once now, and once on the next frame, to catch clients that report 0 sizes during initial construction.
	ApplyLayout()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, ApplyLayout)
	end

	-- Text renderer fallback (ScrollingMessageFrame) for clients where SimpleHTML does not render reliably
	if not Reputable.gui.text_main then
		local function createTextFrame(key, justify)
			local f = CreateFrame("ScrollingMessageFrame", nil, cont.main)
			f:SetFading(false)
			f:SetMaxLines(6000)
			f:SetJustifyH(justify or "LEFT")
			f:SetJustifyV("TOP")
			if f.SetWordWrap then f:SetWordWrap(true) end
			if f.SetHyperlinksEnabled then f:SetHyperlinksEnabled(true) end
			-- Some Anniversary builds are stricter about the optional "flags" argument; pass an empty string.
			f:SetFont(STANDARD_TEXT_FONT, 12, "")
			f:SetInsertMode("BOTTOM")
			if f.SetHyperlinksEnabled then f:SetHyperlinksEnabled(true) end
			f:EnableMouse(true)
			f:EnableMouseWheel(true)
			f:SetScript("OnMouseWheel", function(self, delta)
				ScrollMain(delta)
			end)
			f:SetScript("OnHyperlinkClick", function(self, link, text, button)
				Reputable:insertChatLink(link, text, button)
				Reputable:setFactionFromHyperLink(link)
			end)
			f:SetScript("OnHyperlinkEnter", function(...) Reputable:OnHyperlinkEnter(...) end)
			f:SetScript("OnHyperlinkLeave", function()
				GameTooltip:Hide()
				Reputable.iconFrame:Hide()
				Reputable.iconFrame.heroic:Hide()
			end)
			Reputable.gui[key] = f
			return f
		end
		createTextFrame("text_main", "LEFT")
		createTextFrame("text_right", "RIGHT")
		-- Centered title FontString above the scrolling content
		do
			local title = cont.main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			title:SetJustifyH("CENTER")
			title:SetJustifyV("TOP")
			title:SetTextColor(1, 1, 1, 1)
			title:SetWordWrap(true)
			Reputable.gui.text_title = title
		end
		-- Put text frames above any scrollframe art
		Reputable.gui.text_main:SetFrameStrata(cont:GetFrameStrata())
		Reputable.gui.text_right:SetFrameStrata(cont:GetFrameStrata())
		Reputable.gui.text_main:SetFrameLevel(cont:GetFrameLevel() + 30)
		Reputable.gui.text_right:SetFrameLevel(cont:GetFrameLevel() + 30)
	end

	for name, _ in pairs(htmlLayers) do
		local __ok, __html = pcall(CreateFrame, "SimpleHTML", "html_" .. name, Reputable.gui.main, "SimpleHTMLTemplate")
		if not __ok then
			__html = CreateFrame("SimpleHTML", "html_" .. name, Reputable.gui.main)
		end
		Reputable.gui["html_" .. name] = __html
		local layer = Reputable.gui["html_" .. name]
		-- Ensure the HTML layers render above scrollframe artwork on clients where
		-- ScrollFrame template pieces can otherwise occlude children.
		layer:SetFrameStrata(cont:GetFrameStrata())
		layer:SetFrameLevel(cont:GetFrameLevel() + 20)
		layer:SetAlpha(0)
		layer:Hide()
		layer.y = 0
		-- Make sure the layer stays visually transparent even if the template includes art.
		StripHTMLBackground(layer)
		-- Points/sizes are handled by ApplyLayout() to avoid client-specific 0-size timing issues.
		-- Give the layer a faint background so "blank" vs "not rendering" is distinguishable.
		if layer.CreateTexture and not layer.__repBg then
			local bg = layer:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(layer)
			if bg.SetColorTexture then bg:SetColorTexture(0, 0, 0, 0.15) end
			layer.__repBg = bg
		end
		--	layer:SetFont('Fonts\\FRIZQT__.TTF', 12);
		setHTMLFont(layer, STANDARD_TEXT_FONT, 12);
		setHTMLSpacing(layer, 6);
		layer.showItemTooltip = true
		layer:SetScript("OnHyperlinkEnter", function(...) Reputable:OnHyperlinkEnter(...) end)
		layer:SetScript("OnHyperlinkLeave",
			function()
				GameTooltip:Hide()
				Reputable.iconFrame:Hide()
				Reputable.iconFrame.heroic:Hide()
			end)
		--	layer:SetScript("OnHyperlinkClick", function(self, link, text, button) SetItemRef(link, text) Reputable:setFactionFromHyperLink( link ) end);
		layer:SetScript("OnHyperlinkClick",
			function(self, link, text, button)
				Reputable:insertChatLink(link, text, button)
				Reputable:setFactionFromHyperLink(link)
			end);
	end
	-- Ensure HTML layers receive a non-zero size now that they exist
	ApplyLayout()
	if C_Timer and C_Timer.After then C_Timer.After(0, ApplyLayout) end


	ApplyLayout()
	if C_Timer and C_Timer.After then C_Timer.After(0, ApplyLayout) end

	for k, v in ipairs(Reputable.guiTabs) do
		if v.name ~= 'midsummer' or (v.name == 'midsummer' and Reputable.midsummer) then
			local title = v.title
			local pagetype = ""
			if v.faction then
				if not Reputable.factionInfo[v.faction] then Reputable.factionInfo[v.faction] = {} end
				if not Reputable.factionInfo[v.faction].name then
					Reputable.factionInfo[v.faction].name =
						GetFactionInfoByID(v.faction) or "Unknown Faction"
				end
				title = REPUTATION .. " " .. Reputable:createLink("faction", v.faction, nil, nil, nil, nil)
				v.label = Reputable.factionInfo[v.faction].name
				v.name = "faction" .. v.faction
				if not v.cat then v.cat = 3 end
			elseif v.instance then
				if type(v.instance) == 'number' then
					if Reputable.attunements[v.instance].name then
						title = Reputable.attunements[v.instance].name
					elseif Reputable.instance[v.instance] then
						title = Reputable.instance[v.instance].name
					end
				else
					title = v.instance
				end
				if not title then title = "Instance: " .. v.instance end
				v.label = title
				v.name = "attune" .. v.instance
				if not v.cat then v.cat = 4 end
				pagetype = "attunement"
			end

			Reputable.guiTabs[v.name] = {
				html = {
					name = v.name,
					i = 1,
					header = "<html><body text='#FFFFFF'><h1 align='center'>" .. title .. "</h1><br/>",
					main = {},
					tab1 = {},
					right = {},
					iRight = 1,
					pagetype = pagetype,
				},
				num = k,
			}
			--if debug() or not v.faction or ( Reputable.factionInfo[ v.faction ] and Reputable.factionInfo[ v.faction ][ playerFaction ] ~= false ) then
			if not v.faction or (Reputable.factionInfo[v.faction] and Reputable.factionInfo[v.faction][playerFaction] ~= false) then
				if not Reputable.guiCats[v.cat].created then
					createSubTitle(cont.menu, Reputable.guiCats[v.cat].name, Reputable.guiCats[v.cat].label)
					Reputable.guiCats[v.cat].created = true
				end
				createMenuBTN(cont.menu, v.name, v.label)
			end
		end
	end

	-- Ensure layout runs after HTML layers exist (some clients report 0 sizes during construction)
	ApplyLayout()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, ApplyLayout)
	end

	cont.menu:SetHeight(30 - cont.menu.y);

	if not page then page = 'dailies' end
	Reputable.tabOpen = page
	makeDataForAllPages()
	Reputable:loadHTML(nil)
end

function Reputable:guiUpdate(skipLogCheck, needsRefresh)
	Reputable:resetDailies(false)
	if not skipLogCheck then
		Reputable:getQuestLog(needsRefresh)
	else
		if Reputable.gui and Reputable.gui:IsVisible() then
			makeDataForAllPages()
			Reputable:loadHTML(nil)
		else
			Reputable.guiNeedsUpdate = true
		end
	end
end

function Reputable:toggleGUI(show, page)
	Reputable:resetDailies(false)
	if Reputable.gui == nil then
		createGUI(page)
	elseif Reputable.gui:IsVisible() and not show then
		Reputable.gui:Hide()
	elseif show ~= false then
		local midsummerCurrencyBags = GetItemCount(23247)
		local midsummerCurrencyTotal = GetItemCount(23247, true)
		if Reputable.midsummerCurrencyTotal and Reputable.midsummerCurrencyTotal ~= midsummerCurrencyTotal or Reputable.midsummerCurrencyBags and Reputable.midsummerCurrencyBags ~= midsummerCurrencyBags then Reputable.guiNeedsUpdate = true end
		if Reputable.guiNeedsUpdate then makeDataForAllPages() end
		Reputable.gui:Show()
		Reputable:loadHTML(page)
	end
end

-- [[ MiniMapIcon ]] --
function Reputable:toggleMiniMap()
	if Reputable_Data.global.mmShow then
		reputableMinimapIcon:Show("Reputable")
	else
		reputableMinimapIcon:Hide("Reputable")
	end
end

local function addPlayerToLDBToolTip(key, show, tooltip)
	if show then
		local k = Reputable_Data[key]
		if k.profile and server == k.profile.server then
			local color = "|c" .. RAID_CLASS_COLORS[k.profile.class].colorStr
			local dailyCount = Reputable:getDailyCount(key)

			if dailyCount > 0 or key == Reputable.profileKey then
				tooltip:AddDoubleLine(color .. k.profile.name,
					"|cffffff00(" .. dailyCount .. " / " .. GetMaxDailyQuests() .. ")|r")
			end
		end
	end
end

local function minimapButtonClick(button)
	if button == "LeftButton" then
		if IsShiftKeyDown() then
			local dungeonDailyText = ""
			if Reputable_Data.global.dailyDungeons[server].dailyNormalDungeon then
				dungeonDailyText = Reputable.instance
					[Reputable.dailyInfo[Reputable_Data.global.dailyDungeons[server].dailyNormalDungeon].instanceID]
					.name
			end
			if Reputable_Data.global.dailyDungeons[server].dailyHeroicDungeon then
				if dungeonDailyText ~= "" then dungeonDailyText = dungeonDailyText .. " & " end
				dungeonDailyText = dungeonDailyText ..
					string.gsub(HEROIC_PREFIX, "%%s",
						Reputable.instance
						[Reputable.dailyInfo[Reputable_Data.global.dailyDungeons[server].dailyHeroicDungeon].instanceID]
						.name)
			end
			if dungeonDailyText ~= "" then
				local resetTime = " || " ..
					(GameTooltipTextRight1:GetText() or LibDBIconTooltipTextRight1:GetText() or "")
				local changeTime = ""
				if Reputable_Data.global.dailyDungeons[server].dailyChangeOffset ~= 0 then
					changeTime = " || " ..
						(GameTooltipTextRight2:GetText() or LibDBIconTooltipTextRight2:GetText() or "")
				end
				dungeonDailyText = DAILY .. " " .. DUNGEONS .. "; " .. dungeonDailyText .. resetTime .. changeTime
				ChatEdit_ActivateChat(DEFAULT_CHAT_FRAME.editBox)
				ChatEdit_InsertLink(dungeonDailyText)
			end
		else
			Reputable:toggleGUI()
		end
	elseif button == "RightButton" then
		OpenOptionsCompat()
	end
end
local function minimapButtonOver(self, tooltip)
	Reputable.DataBrokerActiveTooltip = tooltip

	Reputable:addonMessage()
	tooltip:AddDoubleLine("|cFF8080FFReputable|r", RESET .. ": " .. SecondsToTime(GetQuestResetTime()))
	if Reputable_Data.global.dailyDungeons[server].dailyChangeOffset ~= 0 then
		local nextChange = GetQuestResetTime() + 3600 * Reputable_Data.global.dailyDungeons[server].dailyChangeOffset
		if nextChange > 86400 then nextChange = nextChange - 86400 end
		tooltip:AddDoubleLine(" ",
			AVAILABLE ..
			" " .. DAILY .. " " .. COMMUNITIES_CREATE_DIALOG_ICON_SELECTION_BUTTON .. ": " .. SecondsToTime(nextChange),
			0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
	end
	tooltip:AddLine(" ")
	--debug( tooltip:GetName() )
	Reputable.addDailiesToToolTip(tooltip)
	if Reputable_Data[Reputable.profileKey].watchedFactionID then
		Reputable.createFactionToolTip(self, Reputable_Data[Reputable.profileKey].watchedFactionID, tooltip)
	else
		addPlayerToLDBToolTip(Reputable.profileKey,
			Reputable_Data.global.ttShowCurrentInList and Reputable_Data.global.profileKeys[Reputable.profileKey],
			tooltip)
		if Reputable_Data.global.ttShowList then
			for key, show in pairs(Reputable_Data.global.profileKeys) do
				if key ~= Reputable.profileKey then
					addPlayerToLDBToolTip(key, show, tooltip)
				end
			end
		end
	end
	local headerMade = false
	for factionID, change in pairs(Reputable.sessionStart.changes) do
		if not headerMade then
			tooltip:AddLine(" ")
			tooltip:AddLine("|cFFFFFFFFThis Session:|r")
			headerMade = true
		end
		local repString = Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions[factionID])
		if change > 0 then change = "+" .. change end
		tooltip:AddDoubleLine(Reputable.factionInfo[factionID].name, repString .. " |cFF8080FF(" .. change .. ")|r")
	end
	if Reputable_Data.global.mmTooltipShowOperations then
		tooltip:AddLine(" ")
		tooltip:AddDoubleLine("|cFFFFFFFF" .. KEY_BUTTON1 .. "|r", "Open")
		tooltip:AddDoubleLine("|cFFFFFFFF" .. KEY_BUTTON2 .. "|r", GAMEOPTIONS_MENU)
		tooltip:AddDoubleLine("|cFFFFFFFF" .. SHIFT_KEY_TEXT .. "-" .. KEY_BUTTON1 .. "|r",
			COMMUNITIES_INVITE_MANAGER_COLUMN_TITLE_LINK .. " " .. DAILY .. " " .. DUNGEONS)
	end
	tooltip.timerLine = 1

	if tooltip:GetName() == "GameTooltip" then
		tooltip.owner = tooltip:GetOwner()
		tooltip:GetOwner().UpdateTooltip = function() Reputable:updateResetTime() end
	else
		reputableDataBroker.tooltipUpdater = C_Timer.NewTicker(0.2, function() Reputable:updateResetTime() end)
	end
end

function Reputable:initMiniMap()
	Reputable_Data.global.mmData.hide = not Reputable_Data.global.mmShow
	reputableDataBroker = LDB:NewDataObject("ReputableLDB", {
		type = "data source",
		label = "Reputable",
		icon = "Interface\\AddOns\\Reputable\\icons\\reputable_icon",
		OnClick = function(self, button)
			minimapButtonClick(button)
		end,
		OnTooltipShow = function(tooltip)
			minimapButtonOver(self, tooltip)
		end,
		OnLeave = function(tooltip)
			if reputableDataBroker.tooltipUpdater then reputableDataBroker.tooltipUpdater:Cancel() end
		end,
	})

	reputableMM = LDB:NewDataObject("Reputable", {
		type = "launcher",
		icon = "Interface\\AddOns\\Reputable\\icons\\reputable_icon",
		OnClick = function(clickedframe, button)
			minimapButtonClick(button)
		end,
		OnTooltipShow = function(tooltip)
			minimapButtonOver(self, tooltip)
		end,
		OnLeave = function(tooltip)
			if reputableDataBroker.tooltipUpdater then reputableDataBroker.tooltipUpdater:Cancel() end
		end,
	})
	reputableMinimapIcon:Register("Reputable", reputableMM, Reputable_Data.global.mmData)

	Reputable:setWatchedFaction()
end

local currentlyWatchedID
function Reputable:setWatchedFaction(factionID)
	if reputableDataBroker then
		currentlyWatchedID = Reputable_Data[Reputable.profileKey].watchedFactionID

		if (factionID == nil and currentlyWatchedID == nil) then
			--reputableDataBroker.label = "Reputable"
			reputableDataBroker.text = ""
		else
			if factionID and (not currentlyWatchedID or currentlyWatchedID ~= factionID) then
				currentlyWatchedID = factionID
			end

			if Reputable.factionInfo[currentlyWatchedID] then
				Reputable_Data[Reputable.profileKey].watchedFactionID = currentlyWatchedID
				--	Reputable:getAllFactions()
				ReputationFrame_Update()

				local repString = Reputable:getRepString(Reputable_Data[Reputable.profileKey].factions
					[currentlyWatchedID])
				--	reputableDataBroker.label = Reputable.factionInfo[ currentlyWatchedID ].name
				reputableDataBroker.text = "|cFF8080FF" ..
					Reputable.factionInfo[currentlyWatchedID].name .. ":|r " .. repString

				if Reputable_Data.global.ldbUseBlizzRepBar then
					local factionIndex = Reputable.factionInfo[currentlyWatchedID].index
					if not factionIndex then factionIndex = 0 end
					SetWatchedFactionIndex(factionIndex)
				end
			else
				--	reputableDataBroker.label = "Reputable"
				reputableDataBroker.text = ""
			end
		end
	end
end
