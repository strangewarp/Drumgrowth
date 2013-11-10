
local Drumgrowth = pd.Class:new():register("drumgrowth-main")

local MIDI = require('MIDI')

-- Recursively copy all sub-tables and sub-items, when copying from one table to another. Invoke as: newtable = deepCopy(oldtable, {})
local function deepCopy(t, t2)
	for k, v in pairs(t) do
		if type(v) ~= "table" then
			t2[k] = v
		else
			local temp = {}
			deepCopy(v, temp)
			t2[k] = temp
	end end
	return t2
end

local function deepPrint(t, tabs) -- DEBUGGING
	for k, v in pairs(t) do
		if type(v) ~= "table" then
			pd.post(string.rep("..|.", tabs) .. k .. " = " .. tostring(v))
		else
			pd.post(string.rep("..|.", tabs) .. "[" .. k .. "]")
			deepPrint(v, tabs + 1)
	end end
end

-- Generate a table with weighting thresholds for every integer divisor of the TPQ value
function Drumgrowth:populateTPQTable()

	local divs = {}

	-- Get all numbers that divide tpq into an integer
	pd.post("Grabbing clean divisors of TPQ...")
	local subtpqdivs = {}
	for i = self.tpq, 1, -1 do
		if (self.tpq / i) == math.floor(self.tpq / i) then
			table.insert(subtpqdivs, i)
	end end
	pd.post("Clean divisors grabbed!")

	-- Populate the TPQ divisors table with weight ranges for all divisors of the TPQ value
	pd.post("Populating TPQ divisor-weights table...")
	local divlow, divhigh = 90, 100
	local divlowreduce, divhighreduce = 50, 25
	for _, v in ipairs(subtpqdivs) do
		table.insert(divs, {v, divlow, divhigh})
		divlow = math.max(1, divlow - divlowreduce)
		divhigh = math.max(1, divhigh - divhighreduce)
	end
	pd.post("TPQ divisor-weights populated!")

	return divs

end

-- Populate beat-attraction table with attraction thresholds
function Drumgrowth:populateAttractionTable(ticks, divs)

	local attract = {}

	pd.post("Populating attraction table with thresholds...")
	for i = 1, ticks do
		for _, v in ipairs(divs) do
			if ((i - 1) % v[1]) == 0 then
				attract[i] = math.random(v[2], v[3])
				break
	end end end
	pd.post("Attraction table populated!")

	return attract

end

-- Grab all base note-values to be used in the sequence
function Drumgrowth:collectBaseNotes(fewest, most, weightbot, weighttop)

	local bases = {}
	local totalweight = 0

	pd.post("Grabbing base notes...")
	for i = 1, math.random(fewest, most) do
		local newnote = {
			weight = math.random(weightbot, weighttop),
			note = math.random(self.low, self.high),
			volume = weight,
		}
		table.insert(bases, newnote)
		totalweight = totalweight + newnote.weight
	end
	pd.post("Base notes grabbed!")

	return bases, totalweight

end

-- Build the initial units of the timeline, favoring repetition of notes that fall on beats
function Drumgrowth:buildInitialChunks(divs, voices, totalvoiceweight)

	local timeline = {}
	local units = {}
	local similar = {}

	pd.post("Filling primordial timeline...")

	pd.post("Building primordial units...")
	repeat
		units, similar = {}, {}
		-- Build a set of units, each containing notes weighted to be most likely to fall on prominent ticks
		for i = 1, 50 do
			units[i] = {}
			for tick = 1, self.tpq do
				for k, v in ipairs(divs) do
					if ((tick - 1) % v[1]) == 0 then
						if math.random(0, 100) < math.random(v[2], v[3]) then
							local testweight = math.random(1, totalvoiceweight)
							for _, vox in ipairs(voices) do
								testweight = testweight - vox.weight
								if testweight <= 0 then
									units[i][tick] = vox
									break
						end end end
						break
		end	end end end
		-- Purge empty units
		for i = #units, 1, -1 do
			if next(units[i]) == nil then
				table.remove(units, i)
		end end
	until #units > 1
	pd.post("Primordial units built!")

	-- Analyze differences between every possible pair of units
	pd.post("Analyzing unit differences...")
	for i = 1, #units do
		similar[i] = similar[i] or {}
		for ii = i, #units do
			similar[ii] = similar[ii] or {}
			if i ~= ii then
				local sim = 0
				for tick = 1, self.tpq do
					if (
						(units[i][tick] == nil)
						and (units[ii][tick] == nil)
					) or (
						(units[i][tick] ~= nil)
						and (units[ii][tick] ~= nil)
						and (units[i][tick].note == units[ii][tick].note)
					)
					then
						sim = sim + 1
				end end
				if sim == self.tpq then -- Disfavor similarity between units that are exactly identical
					sim = 0
				end
				table.insert(similar[i], {ii, sim})
				table.insert(similar[ii], {i, sim})
			else
				table.insert(similar[i], {i, 0}) -- Disfavor a unit's similarity to itself
	end end end
	pd.post("Unit differences analyzed!")

	-- Sort all similarity-tables by similarity-threshold
	pd.post("Sorting units by similarity threshold...")
	for i = 1, #similar do
		table.sort(similar[i], function (a, b) return a[2] > b[2] end)
	end
	pd.post("Units sorted!")

	-- Get chunk-order sequence
	pd.post("Generating primordial chunk order...")
	local bases = 3
	local order = {}
	repeat
		local types = {}
		table.insert(order, math.random(1, bases))
		for i = 1, #order do
			if types[order[i]] == nil then
				types[order[i]] = true
		end end
	until #types == bases
	pd.post("Primordial chunk order generated!")

	-- Grab units at random from the base units, and assemble tables of similar units around them
	pd.post("Gathering similar tables...")
	local usim, u = {}, {}
	for i = 1, bases do
		local ubase = math.random(1, #units)
		table.insert(u, similar[ubase][((i - 1) % #similar[ubase]) + 1][1])
	end
	for i = 1, bases do
		usim[i] = {u[i], similar[u[i]][1][1]}
	end
	pd.post("Similar tables gathered!")

	-- Use the sets of similar units to build the timeline
	pd.post("Combining ordered similar chunks...")
	local uindex, elapsed = order[1], 0
	while #timeline < (self.beats * self.tpq) do
		local urand = math.random(#usim[uindex])
		for i = 1, self.tpq do
			local tick = (elapsed * self.tpq) + i
			timeline[tick] = {}
			if (units[usim[uindex][urand]] ~= nil)
			and (units[usim[uindex][urand]][i] ~= nil)
			then
				local outref = units[usim[uindex][urand]][i]
				local outpiece = {
					["note"] = outref.note,
					["weight"] = outref.weight,
					["volume"] = math.random(outref.weight, 127),
				}
				table.insert(timeline[tick], outpiece)
		end end
		uindex = order[(uindex % #order) + 1]
		elapsed = elapsed + 1
	end
	pd.post("Ordered similar chunks combined!")

	pd.post("Primordial timeline filled!")

	return timeline

end

-- Pepper some incidental notes into the timeline, favoring prominent beats
function Drumgrowth:pepperIncidentalNotes(timeline, attract, voices, totalvoiceweight)

	pd.post("Peppering timeline with incidental notes...")
	for i = 1, #timeline do
		local randval = 0
		for i = 1, math.max(1, math.floor(self.tpq / self.beats)) do
			randval = math.random(math.random(randval, 100), 100)
		end
		if randval < attract[i] then
			local selectvoice = {note = 1, weight = 1, volume = 1} -- dummy values
			local randvoice = math.random(totalvoiceweight)
			for k, v in ipairs(voices) do
				randvoice = randvoice - v.weight
				if randvoice <= 0 then
					selectvoice = v
					break
			end end
			selectvoice.volume = math.max(10, math.random(attract[i], 127))
			local insertok = true
			for k, v in pairs(timeline[i]) do
				if selectvoice.note == v.note then
					insertok = false
					break
			end end
			if insertok then
				table.insert(timeline[i], selectvoice)
	end end end
	pd.post("Incidental notes peppered!")

	return timeline

end

-- Slice the timeline into Markov chains, organized by the notes that precede them
function Drumgrowth:generateMarkovChains(timeline, chains)

	pd.post("Generating Markov chains from contents of timeline...")

	for i = 1, #timeline do
		local linkbot = i - math.floor(self.chainunit / 2)
		local slice = {}
		for point = i + 1, i + self.chainunit do
			if timeline[((point - 1) % #timeline) + 1][1] ~= nil then
				table.insert(slice, timeline[((point - 1) % #timeline) + 1][1])
		end end
		local composite = ""
		for lp = i, linkbot, -1 do -- Generate increasingly specific Markov link composites for the chain, each of which is used to index the current slice
			local entry = ((lp - 1) % #timeline) + 1
			composite = ((timeline[entry][1] and timeline[entry][1].note) or -1) .. (((composite:len() > 0) and "_") or "") .. composite
			if chains[composite] == nil then
				chains[composite] = {}
			end
			table.insert(chains[composite], slice) -- Insert the new slice into its chain table, indexed by its preceding notes
	end end

	pd.post("Markov chains generated!")

	return chains

end

-- Overlay Markov chains onto a timeline that contains notes, based on the contents of a chains table
function Drumgrowth:overlayMarkovChains(timeline, attract, chains)

	-- Loop over the timeline multiple times, favoring notes that lay on wide denominators and laying down Markov chains thereafter
	pd.post("Overlaying Markov chains onto established timeline...")
	for tick = 1, #timeline, self.chainunit do
		if math.random(0, 100) < attract[tick] then

			local linkbot = (((tick - math.floor(self.chainunit / 2)) - 1) % #timeline) + 1
			local linkorder, checkorder = {}, {}
			local cpoint = ((linkbot - 2) % #timeline) + 1

			-- Grab the series of linking notes that occur directly before the current tick
			local arrtab = false
			repeat
				cpoint = (cpoint % #timeline) + 1
				local inval = (next(timeline[cpoint]) and timeline[cpoint][1].note) or -1
				if arrtab or ((not arrtab) and (cpoint == tick)) then
					arrtab = true
					table.insert(checkorder, inval)
				else
					table.insert(linkorder, inval)
				end
			until #checkorder == self.chainunit

			-- Identify the chains with the closest match to the preceding ticks
			local selection = false
			for i = 1, #linkorder do
				local composite = table.concat(linkorder, "_")
				if chains[composite] ~= nil then
					local chainsame = true
					for icheck = 1, self.chainunit do
						if chains[composite][icheck] ~= checkorder[icheck] then
							chainsame = false
					end end
					if chainsame then -- Discard chains that are identical to the timeline sections they would be overlaid upon
						table.remove(linkorder, 1)
					else
						selection = composite
						break
					end
				else
					table.remove(linkorder, 1)
			end end
			local usechain = 0
			if selection then
				usechain = chains[selection][math.random(#chains[selection])]
			else -- If no chains match the preceding ticks, pick a beat-starting chain at random
				local goodpoint = false
				repeat
					local rnewpoint = (math.random(#timeline / self.tpq) * self.tpq) - (self.tpq - 1)
					goodpoint = timeline[rnewpoint][math.random(#rnewpoint)].note or false
				until goodpoint
				usechain = chains[goodpoint][math.random(#chains[goodpoint])]
			end

			-- Add the current Markov chain section's notes to the timeline
			for k, v in ipairs(usechain) do
				local sect = (((tick + (k - 1)) - 1) % #timeline) + 1
				local noterepeat = false
				if next(timeline[sect]) then
					for n in pairs(timeline[sect]) do
						if timeline[sect][n].note == v.note then
							noterepeat = true
							break
				end end end
				if not noterepeat then
					--if math.random(0, 100) < attract[sect] then 
					table.insert(timeline[sect], v)
			end end
	end end
	pd.post("Markov chains overlaid!")

	return timeline

end

-- Organize subsections of the timeline into repeating chunks
function Drumgrowth:destructiveChunkRepeat(timeline, reps)

	pd.post("Performing destructive chunk repeat...")

	local chunks = {}
	local newtimeline = {}

	-- Move subsections of the timeline into their corresponding chunks
	for i = 1, #timeline do
		local sect = math.ceil(i / self.tpq)
		if chunks[sect] == nil then
			chunks[sect] = {}
		end
		table.insert(chunks[sect], timeline[i])
	end

	-- Replace some chunks with other chunks
	local rand1 = math.random(#chunks)
	while reps > 0 do
		local rand2 = 0
		repeat
			rand2 = math.random(#chunks)
		until (rand1 ~= rand2) or (#chunks == 1)
		chunks[rand2] = deepCopy(chunks[rand1], {})
		reps = reps - 1
	end

	-- Recombine chunk contents into a new timeline
	for i = 1, #chunks do
		for _, v in ipairs(chunks[i]) do
			table.insert(newtimeline, v)
	end end

	pd.post("Destructive chunk repeat complete!")

	return newtimeline

end

-- Shit around some errant notes to more prominent ticks, deleting those that stack, to prevent formation of overly cluttered sequences
function Drumgrowth:shiftErrantNotes(timeline, attract)

	pd.post("Shifting errant notes...")
	local templine = deepCopy(timeline, {})
	for i = 1, #templine do
		for note = #timeline[i], 1, -1 do
			if math.random(0, math.random(0, 100)) > attract[i] then
				local movenote = table.remove(timeline[i], note)
				local newpos = i
				local direction = ((math.random(0, 1) == 1) and 1) or -1
				while math.random(1, 100) < attract[newpos] do
					newpos = (((newpos + direction) - 1) % #templine) + 1
				end
				local alreadythere = false
				for _, v in pairs(templine[newpos]) do
					if movenote.note == v.note then
						alreadythere = true
						break
				end end
				if not alreadythere then
					table.insert(timeline[newpos], movenote)
	end end end end
	pd.post("Errant notes shifted!")

	return timeline

end

-- Humanize the volume levels of every note in the timeline
function Drumgrowth:varyNoteVolumes(timeline)

	pd.post("Humanizing volume levels...")
	for i = 1, #timeline do
		for k, v in pairs(timeline[i]) do
			if v.volume > -1 then
				local volmod = math.floor(v.volume * 0.2)
				timeline[i][k].volume = math.max(10, math.min(127, math.random(v.volume - volmod, v.volume + volmod)))
	end end end
	pd.post("Volume levels humanized!")

	return timeline

end

function Drumgrowth:initialize(sel, atoms)

	-- 1. Loadbang
	-- 2. User prefs:
		-- Savefile name,
		-- Seed number,
		-- Total beats in sequence,
		-- Beats per minute,
		-- Ticks per quarter note,
		-- Channel,
		-- Sustain length,
		-- Note range bottom,
		-- Note range top,
		-- Markov chain unit size,
		-- Markov mechanism passes
	-- 3. GENERATE A MIDI FILE bang
	self.inlets = 3

	self.outlets = 0

	self.savepath = "C:/Users/Christian/My Documents/MUSIC_STAGING/" -- CHANGE THIS TO REFLECT YOUR DIRECTORY STRUCTURE
	self.savename = "default"
	self.seed = 0
	self.beats = 16
	self.bpm = 120
	self.tpq = 24
	self.channel = 9
	self.sustain = 4
	self.low = 27
	self.high = 87
	self.chainunit = 8
	self.passes = 1

	return true

end

-- On loadbang, after all Pd objects are initialized...
function Drumgrowth:in_1_bang()
	-- Fill user-input boxes with default values, to prevent input weirdness
	pd.send("dg-savename-r", "symbol", {self.savename})
	pd.send("dg-seed-r", "float", {self.seed})
	pd.send("dg-beats-r", "float", {self.beats})
	pd.send("dg-bpm-r", "float", {self.bpm})
	pd.send("dg-tpq-r", "float", {self.tpq})
	pd.send("dg-chan-r", "float", {self.channel})
	pd.send("dg-sustain-r", "float", {self.sustain})
	pd.send("dg-rangebot-r", "float", {self.low})
	pd.send("dg-rangetop-r", "float", {self.high})
	pd.send("dg-markovunit-r", "float", {self.chainunit})
	pd.send("dg-markovpasses-r", "float", {self.passes})
end

-- Get preferences from user-input apparatus
function Drumgrowth:in_2_list(n)
	self.savename, self.seed, self.beats, self.bpm, self.tpq, self.channel, self.sustain, self.low, self.high, self.chainunit, self.passes = unpack(n)
	self.beats = math.max(1, self.beats)
	self.bpm = math.max(1, self.bpm)
	self.tpq = math.max(1, self.tpq)
	self.channel = math.min(15, math.max(0, self.channel))
	local low, high = math.min(127, math.max(0, self.low)), math.min(127, math.max(0, self.high))
	if low > high then
		low, high = high, low
	end
	self.low = low
	self.high = high
	self.chainunit = math.max(1, self.chainunit)
	self.passes = math.max(1, self.passes)
	pd.post("Savefile name: " .. self.savepath .. self.savename)
	pd.post("Seed number: " .. self.seed)
	pd.post("Total beats in loop: " .. self.beats)
	pd.post("Beats per minute: " .. self.bpm)
	pd.post("Ticks per beat: " .. self.tpq)
	pd.post("MIDI Channel: " .. self.channel)
	pd.post("MIDI sustain length: " .. self.sustain)
	pd.post("MIDI Note range: " .. self.low .. "-" .. self.high)
	pd.post("Markov chain unit size: " .. self.chainunit)
	pd.post("Markov chain passes: " .. self.passes)
	pd.post("")
end

-- Get SAVE MIDI FILE bang
function Drumgrowth:in_3_bang()

	pd.post("Generating sequence...")

	math.randomseed(self.seed)

	local timeline, chains = {}, {}
	local ticks = self.tpq * self.beats

	local divs = self:populateTPQTable()
	local attract = self:populateAttractionTable(ticks, divs)
	local voices, totalvoiceweight = self:collectBaseNotes(3, 10, 33, 100)

	-- Sort voices by threshold weight
	pd.post("Sorting note priorities by threshold weight...")
	table.sort(voices, function (a, b) return a.weight > b.weight end)
	pd.post("Note priorities sorted!")

	-- Initial population of the timeline
	timeline = self:buildInitialChunks(divs, voices, totalvoiceweight)
	timeline = self:pepperIncidentalNotes(timeline, attract, voices, totalvoiceweight)

	-- Modification of the timeline
	for i = 1, self.passes do
		pd.post("Starting Markov pass " .. i .. "...")
		chains = self:generateMarkovChains(timeline, {})
		timeline = self:overlayMarkovChains(timeline, attract, chains)
		pd.post("Finished Markov pass " .. i .. "!")
	end
	pd.post("Completed Markov passes!")
	timeline = self:shiftErrantNotes(timeline, attract)
	--timeline = self:destructiveChunkRepeat(timeline, math.floor(self.beats / 2))
	timeline = self:varyNoteVolumes(timeline)

	-- Fabricate a Format 1 MIDI score template
	pd.post("Populating score...")
	local score = {
		[self.channel + 1] = {
			{"set_tempo", 0, 60000000 / self.bpm}, -- Tempo: microseconds per beat
			{"end_track", #timeline - 1}, -- End track at last beat
			{"time_signature", 0, 4, 4, self.tpq, 8}, -- Time signature: numerator, denominator, ticks per 1/4, 32nds per 1/4
		},
	}
	for i = 1, 16 do
		score[i] = score[i] or {}
	end

	-- Populate score with notes from the timeline table, following MIDI.lua's table formatting requirements
	for tick, v in pairs(timeline) do
		for index, item in pairs(v) do
			table.insert(score[self.channel + 1], {"note", tick - 1, math.min(#timeline - tick, self.sustain), self.channel, item.note, item.volume})
	end end

	table.insert(score, 1, self.tpq)

	pd.post("Score populated!")

	-- Save the table into a MIDI file, using MIDI.lua functions
	pd.post("Saving file: " .. self.savepath .. self.savename .. ".mid")
	local midifile = assert(io.open(self.savepath .. self.savename .. ".mid", 'w'))
	midifile:write(MIDI.score2midi(score))
	midifile:close()
	pd.post("Saved file: " .. self.savepath .. self.savename .. ".mid!")

	pd.post("Sequence generated! Success!")
	pd.post("")

end
