local Random = {}
Random.__index = Random

function Random.new(seed)
	seed = math.floor(math.abs(seed or 1)) % 2147483647
	if seed == 0 then
		seed = 1
	end
	return setmetatable({ state = seed }, Random)
end

function Random:nextInteger(maximum)
	self.state = (self.state * 48271) % 2147483647
	return (self.state % maximum) + 1
end

function Random:shuffle(values)
	for index = #values, 2, -1 do
		local swapIndex = self:nextInteger(index)
		values[index], values[swapIndex] = values[swapIndex], values[index]
	end
	return values
end

return Random
