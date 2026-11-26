-- Minimal Roblox Vector3 / CFrame stand-ins so RideKit maths can be tested
-- outside Roblox (same conventions: right-handed, Y up, LookVector = -Z column,
-- CFrame.Angles(x, y, z) = Rx * Ry * Rz, p1 = p0 * C0 * T * C1:Inverse()).

local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return V.new(v.X / m, v.Y / m, v.Z / m)
	end
	return V[k]
end
function V.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return V.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return V.new(a.X * b, a.Y * b, a.Z * b) end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return V.new(a.X / b, a.Y / b, a.Z / b) end
V.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b)
	return V.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V.Lerp(a, b, t) return a + (b - a) * t end
V.zero = V.new(0, 0, 0)
V.xAxis = V.new(1, 0, 0)
V.yAxis = V.new(0, 1, 0)
V.zAxis = V.new(0, 0, 1)

-- CFrame: position p + rotation columns x, y, z
local C = {}
local function mk(p, x, y, z)
	return setmetatable({ p = p, x = x, y = y, z = z }, C)
end
C.__index = function(c, k)
	if k == "Position" then return c.p
	elseif k == "Rotation" then return mk(V.zero, c.x, c.y, c.z)
	elseif k == "LookVector" then return -c.z
	elseif k == "RightVector" then return c.x
	elseif k == "UpVector" then return c.y
	elseif k == "X" then return c.p.X
	elseif k == "Y" then return c.p.Y
	elseif k == "Z" then return c.p.Z
	end
	return C[k]
end
local function rotv(c, v) return c.x * v.X + c.y * v.Y + c.z * v.Z end
function C.new(a, b, c_, ...)
	if a == nil then return mk(V.zero, V.xAxis, V.yAxis, V.zAxis) end
	if type(a) == "table" then return mk(a, V.xAxis, V.yAxis, V.zAxis) end
	local r = { ... }
	if #r == 9 then -- rows R00 R01 R02 / R10 ... -> columns
		return mk(V.new(a, b, c_), V.new(r[1], r[4], r[7]), V.new(r[2], r[5], r[8]), V.new(r[3], r[6], r[9]))
	end
	return mk(V.new(a, b, c_), V.xAxis, V.yAxis, V.zAxis)
end
function C.fromMatrix(p, x, y, z)
	z = z or x:Cross(y).Unit
	return mk(p, x, y, z)
end
function C.fromAxisAngle(axis, a)
	local u = axis.Unit
	local c, s, t = math.cos(a), math.sin(a), 1 - math.cos(a)
	local function col(e)
		-- Rodrigues: R e = e cos + (u x e) sin + u (u.e)(1-cos)
		return e * c + u:Cross(e) * s + u * (u:Dot(e) * t)
	end
	return mk(V.zero, col(V.xAxis), col(V.yAxis), col(V.zAxis))
end
function C.Angles(rx, ry, rz)
	return C.fromAxisAngle(V.xAxis, rx) * C.fromAxisAngle(V.yAxis, ry) * C.fromAxisAngle(V.zAxis, rz)
end
C.fromEulerAnglesXYZ = C.Angles
function C.fromEulerAnglesYXZ(rx, ry, rz)
	return C.fromAxisAngle(V.yAxis, ry) * C.fromAxisAngle(V.xAxis, rx) * C.fromAxisAngle(V.zAxis, rz)
end
function C.lookAt(at, target, up)
	up = up or V.yAxis
	local look = (target - at).Unit
	local z = -look
	local x = up:Cross(z).Unit
	local y = z:Cross(x)
	return mk(at, x, y, z)
end
C.__mul = function(a, b)
	if getmetatable(b) == C then
		return mk(a.p + rotv(a, b.p), rotv(a, b.x), rotv(a, b.y), rotv(a, b.z))
	end
	return a.p + rotv(a, b)
end
function C.Inverse(c)
	-- transpose rows
	local x = V.new(c.x.X, c.y.X, c.z.X)
	local y = V.new(c.x.Y, c.y.Y, c.z.Y)
	local z = V.new(c.x.Z, c.y.Z, c.z.Z)
	local r = mk(V.zero, x, y, z)
	return mk(-(rotv(r, c.p)), x, y, z)
end
function C.ToObjectSpace(a, b) return a:Inverse() * b end
function C.ToWorldSpace(a, b) return a * b end
function C.PointToWorldSpace(a, v) return a * v end
function C.PointToObjectSpace(a, v) return a:Inverse() * v end
function C.VectorToWorldSpace(a, v) return rotv(a, v) end
function C.VectorToObjectSpace(a, v) return rotv(a:Inverse(), v) end
function C.GetComponents(c)
	return c.p.X, c.p.Y, c.p.Z, c.x.X, c.y.X, c.z.X, c.x.Y, c.y.Y, c.z.Y, c.x.Z, c.y.Z, c.z.Z
end

return { Vector3 = V, CFrame = C }
