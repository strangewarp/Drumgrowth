
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
		end
	end
	return t2
end

-- Organize subsections of the timeline into repeating chunks
function Drumgrowth:destructiveChunkRepeat(timeline, reps)

	local chunks = {}

	for i = 1, #timeline / self.tpq do
		chunks[i] = {}
		local subpoint = ((i - 1) * self.tpq) + 1
		for tick = subpoint, subpoint + (#timeline / self.tpq) - 1 do
			table.insert(chunks[i], timeline[tick])
		end
	end

	while reps > 0 do
		local rand1, rand2 = math.random(#chunks), 0
		repeat
			rand2 = math.random(#chunks)
		until (rand1 ~= rand2) or (#chunks == 1)
		chunks[rand1] = deepCopy(chunks[rand2], {})
		reps = reps - 1
	end

	for k, v in ipairs(chunks) do
		for i = 1, #v do
			timeline[i + (#v * (k - 1))] = v[i]
		end
	end

	return timeline

end

function Drumgrowth:initialize(sel, atoms)

	-- 1. User prefs:
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
	-- 2. GENERATE A MIDI FILE bang
	self.inlets = 2

	self.outlets = 0

	self.savepath = "C:/Users/Christian/My Documents/MUSIC_STAGING/" -- CHANGE THIS TO REFLECT YOUR DIRECTORY STRUCTURE
	self.savename = "default"
	self.seed = 2356
	self.beats = 32
	self.bpm = 120
	self.tpq = 32
	self.channel = 9
	self.sustain = 4
	self.low = 27
	self.high = 87
	self.chainunit = 8
	self.passes = 16

	return true

end

function Drumgrowth:in_1_list(n)
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

function Drumgrowth:in_2_bang()

	pd.post("Gathering initial variables...")

	math.randomseed(self.seed)

	local score = {}

	local voices = {}
	local attract = {}
	local phrase = {}
	local chains = {}
	local timeline = {}

	local divs = {
		{64, 90, 100},
		{32, 80, 100},
		{16, 0, 100},
		{8, 0, 65},
		{4, 0, 20},
		{2, 0, 10},
		{1, 0, 5}, -- DO NOT REMOVE - an entry that starts with 1 is required for the tables to populate correctly
	}

	local newvoicebounds = {
		{1, 5, 50, 100},
		{1, 10, 1, 50},
	}

	local totalvoiceweight = 0

	local ticks = self.tpq * self.beats

	local linksize = math.floor(self.chainunit / 2)

	pd.post("Initial variables gathered!")

	-- Populate timeline with the total number of ticks
	pd.post("Fabricating timeline table...")
	for i = 1, ticks do
		timeline[i] = {}
	end
	pd.post("Timeline table fabricated!")

	-- Populate beat-attraction table with attraction thresholds
	pd.post("Populating attraction table with thresholds...")
	for i = 1, ticks do
		for _, v in ipairs(divs) do
			if ((i - 1) % v[1]) == 0 then
				attract[i] = math.random(v[2], v[3])
				break
			end
		end
	end
	pd.post("Attraction table populated!")

	-- Grab number of base voices
	pd.post("Grabbing base notes...")
	for _, v in pairs(newvoicebounds) do
		for i = 1, math.random(v[1], v[2]) do
			local newnote = {
				weight = math.random(v[3], v[4]),
				note = math.random(self.low, self.high),
				volume = weight,
			}
			table.insert(voices, newnote) -- Put new voice data into voices table
			totalvoiceweight = totalvoiceweight + newnote.weight
		end
	end
	pd.post("Base notes grabbed!")

	-- Sort voices by threshold weight
	pd.post("Sorting note priorities by threshold weight...")
	table.sort(voices, function (a, b) return a.weight > b.weight end)
	pd.post("Note priorities sorted!")

	-- Lay down some originator notes into the timeline, favoring prominent denominators
	pd.post("Populating timeline with initial notes...")
	for i = 1, #timeline do
		if math.random(0, 100) < attract[i] then
			local selectvoice = {note = 1, weight = 1, volume = 1} -- dummy values
			local randvoice = math.random(totalvoiceweight)
			for k, v in ipairs(voices) do
				randvoice = randvoice - v.weight
				if randvoice <= 0 then
					selectvoice = v
					break
				end
			end
			selectvoice.volume = math.random(attract[i], 127)
			table.insert(timeline[i], selectvoice)
		end
	end
	pd.post("Initial notes populated!")

	-- Slice the elongated beat-phrase into Markov chains, organized by the notes that precede them
	pd.post("Generating Markov chains from contents of timeline...")
	for i = 1, #timeline do
		local linkbot = i - linksize
		local slice = {}
		for point = i + 1, i + self.chainunit do
			table.insert(slice, timeline[((point - 1) % #timeline) + 1][1] or {note = -1, weight = -1, volume = -1})
		end
		local composite = ""
		for lp = i, linkbot, -1 do -- Generate increasingly specific Markov link composites for the chain, each of which is used to index the current slice
			local entry = ((lp - 1) % #timeline) + 1
			composite = ((next(timeline[entry]) and timeline[entry][1].note) or -1) .. (((composite:len() > 0) and "_") or "") .. composite
			if chains[composite] == nil then
				chains[composite] = {}
			end
			table.insert(chains[composite], slice) -- Insert the new slice into its chain table, indexed by its preceding notes
		end
	end
	pd.post("Markov chains generated!")

	-- Repeat randomly-chosen sections of the timeline
	pd.post("Performing destructive chunk repeat...")
	timeline = self:destructiveChunkRepeat(timeline, math.random(math.ceil(self.beats / 2), self.beats))
	pd.post("Destructive chunk repeat complete!")

	-- Loop over the timeline multiple times, favoring notes that lay on wide denominators and laying down Markov chains thereafter
	pd.post("Overlaying Markov chains onto established timeline...")
	for i = 1, self.passes do
		pd.post("Iteration " .. i .. "...")
		for tick = 1, #timeline do
			if math.random(0, 100) < attract[tick] then

				local linkbot = (((tick - linksize) - 1) % #timeline) + 1
				local linkorder = {}
				local cpoint = linkbot - 1
				local selection = false

				-- Grab the series of linking notes that occur directly before the current tick
				repeat
					cpoint = (cpoint % #timeline) + 1
					table.insert(linkorder, (next(timeline[cpoint]) and timeline[cpoint][1].note) or -1)
				until cpoint == tick

				-- Identify the chains with the closest match to the preceding ticks
				for i = 1, #linkorder do
					local composite = table.concat(linkorder, "_")
					if chains[composite] ~= nil then
						selection = composite
						break
					else
						table.remove(linkorder, 1)
					end
				end
				local usechain = 0
				if selection then
					usechain = chains[selection][math.random(#chains[selection])]
				else -- If no chains match the preceding ticks, pick a beat-starting chain at random
					local goodpoint = false
					repeat
						goodpoint = timeline[(math.random(#timeline / self.tpq) * self.tpq) - (self.tpq - 1)][1].note or false
					until goodpoint
					usechain = chains[goodpoint][math.random(#chains[goodpoint])]
				end

				-- Add the current Markov chain section's notes to the timeline
				for k, v in ipairs(usechain) do
					if v ~= -1 then
						local sect = (((tick + (k - 1)) - 1) % #timeline) + 1
						local noterepeat = false
						if next(timeline[sect])
						and (timeline[sect][1].note ~= nil)
						and (timeline[sect][1].note == v)
						then
							noterepeat = true
							break
						end
						if not noterepeat then
							if math.random(0, 100) < attract[sect] then 
								table.insert(timeline[sect], v)
							end
						end
					end
				end

			end
		end
	end
	pd.post("Markov chains overlaid!")

	-- Repeat randomly-chosen sections of the timeline, again
	pd.post("Performing destructive chunk repeat (second round)...")
	timeline = self:destructiveChunkRepeat(timeline, math.random(math.ceil(self.beats / 2), self.beats))
	pd.post("Destructive chunk repeat (second round) complete!")

	-- Fabricate a score template
	pd.post("Creating score template...")
	local score = {
		self.tpq,
		{
			{"set_tempo", 0, 60000000 / self.bpm}, -- Tempo: microseconds per beat
			{"time_signature", 0, 4, 4, self.tpq, 8}, -- Time signature: numerator, denominator, ticks per 1/4, 32nds per 1/4
		},
	}

	-- Populate score with notes from the timeline table, following MIDI.lua's table formatting requirements
	pd.post("Populating score...")
	for tick, v in pairs(timeline) do
		if next(v) ~= nil then
			for _, item in pairs(v) do
				table.insert(score[2], {"note", tick, self.sustain, self.channel, item.note, item.volume})
			end
		end
	end
	pd.post("Score populated!")

	-- Save the table into a MIDI file, using MIDI.lua functions
	pd.post("Saving file: " .. self.savepath .. self.savename .. ".mid")
	local midifile = assert(io.open(self.savepath .. self.savename .. ".mid", 'w'))
	midifile:write(MIDI.score2midi(score))
	midifile:close()
	pd.post("Saved file: " .. self.savepath .. self.savename .. ".mid!")
	pd.post("")

end
